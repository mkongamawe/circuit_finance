# Load libraries
library(readr)
library(dplyr)
library(ggplot2)
library(lubridate)
library(tidyr)

# FIX: Disable scientific notation globally
options(scipen = 999)

# FIX: Helper function to format axis labels with commas (e.g., 125,000)
comma_format <- function(x) format(x, scientific = FALSE, big.mark = ",")

# 1. Parse Command Line Arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    stop("Missing arguments. Usage: Rscript plotter.R <start_date> <end_date>")
}
start_date <- ymd(args[1])
end_date <- ymd(args[2])

# 2. Setup Directories and Load Data
plot_dir <- "/data/plots/"
if (!dir.exists(plot_dir)) {
    dir.create(plot_dir, recursive = TRUE)
}

ledger_df <- read_csv(
    "/data/exports/ledger_export.csv",
    show_col_types = FALSE
) %>%
    mutate(date = as.Date(date))
targets_df <- read_csv(
    "/data/exports/targets_export.csv",
    show_col_types = FALSE
)

# Helper: Generate STRICTLY ordered chronological time labels
get_time_labels <- function(s_date, e_date, by_quarter) {
    dates <- seq(
        floor_date(s_date, "month"),
        floor_date(e_date, "month"),
        by = "month"
    )
    if (by_quarter) {
        q_map <- c(
            "1" = "Jan-Mar",
            "2" = "Apr-Jun",
            "3" = "Jul-Sep",
            "4" = "Oct-Dec"
        )
        labels <- unique(paste(
            q_map[as.character(quarter(dates))],
            year(dates)
        ))
    } else {
        labels <- unique(format(dates, "%b %Y"))
    }
    return(labels)
}

# --- PLOT 1 & 2: Cumulative Line Charts (YTD Trajectory) ---
save_trend_bars <- function(
    df,
    s_date,
    e_date,
    filter_cat_pattern,
    title,
    filename
) {
    num_months <- interval(s_date, e_date) %/% months(1) + 1
    prev_start <- s_date - months(num_months)
    prev_end <- s_date - days(1)

    trend_data <- df %>%
        filter(
            grepl(filter_cat_pattern, category, ignore.case = TRUE),
            transaction_type == "Income"
        )

    get_cumulative_data <- function(data_subset, start_d, end_d, period_name) {
        all_months <- tibble(
            period_month = 1:num_months,
            month_label = format(
                seq(
                    floor_date(start_d, "month"),
                    by = "month",
                    length.out = num_months
                ),
                "%b"
            )
        )

        subset <- data_subset %>% filter(date >= start_d, date <= end_d)
        if (nrow(subset) > 0) {
            subset <- subset %>%
                mutate(
                    period_month = interval(
                        floor_date(start_d, "month"),
                        floor_date(date, "month")
                    ) %/%
                        months(1) +
                        1
                ) %>%
                group_by(period_month) %>%
                summarise(amount = sum(amount), .groups = 'drop')
        } else {
            subset <- tibble(period_month = integer(), amount = numeric())
        }

        all_months %>%
            left_join(subset, by = "period_month") %>%
            replace_na(list(amount = 0)) %>%
            arrange(period_month) %>%
            mutate(
                cumulative_amount = cumsum(amount),
                period = period_name,
                display_label = factor(
                    paste0("M", period_month, "\n", month_label),
                    levels = paste0("M", period_month, "\n", month_label)
                )
            )
    }

    combined_data <- bind_rows(
        get_cumulative_data(
            trend_data,
            prev_start,
            prev_end,
            "Previous Period"
        ),
        get_cumulative_data(trend_data, s_date, e_date, "Current Period")
    )

    if (nrow(combined_data) > 0) {
        p <- ggplot(
            combined_data,
            aes(
                x = display_label,
                y = cumulative_amount,
                color = period,
                group = period
            )
        ) +
            geom_line(linewidth = 1.5) +
            geom_point(size = 3) +
            scale_color_manual(
                values = c(
                    "Previous Period" = "#9E9E9E",
                    "Current Period" = "#1976D2"
                )
            ) +
            scale_y_continuous(labels = comma_format) + # <--- FIX APPLIED
            labs(
                title = paste(title, "(Cumulative)"),
                x = "Relative Month",
                y = "Cumulative Amount (KSh)",
                color = NULL
            ) +
            theme_minimal() +
            theme(
                text = element_text(family = "sans"),
                plot.title = element_text(face = "bold", size = 12),
                legend.position = "bottom",
                panel.grid.minor = element_blank()
            )

        ggsave(
            paste0(plot_dir, filename),
            plot = p,
            width = 10,
            height = 5,
            dpi = 300
        )
        cat(sprintf("✅ Saved %s\n", filename))
    }
}

# --- PLOT 3: Church Assessment Lollipop Chart ---
save_assessment_church_target_bars <- function(df, s_date, e_date, t_df) {
    num_months <- interval(s_date, e_date) %/% months(1) + 1

    inc_targets <- t_df %>%
        filter(category == "Assessment_Income") %>%
        mutate(period_target = monthly_target * num_months)

    actuals <- df %>%
        filter(
            date >= s_date,
            date <= e_date,
            category == "Assessment Received",
            transaction_type == "Income"
        )

    if (nrow(actuals) > 0 && nrow(inc_targets) > 0) {
        actual_sum <- actuals %>%
            group_by(description) %>%
            summarise(amount = sum(amount), .groups = 'drop')

        valid_churches <- unique(inc_targets$Entity)
        plot_data <- tibble(Entity = valid_churches) %>%
            left_join(actual_sum, by = c("Entity" = "description")) %>%
            left_join(
                inc_targets %>% select(Entity, period_target),
                by = "Entity"
            ) %>%
            replace_na(list(amount = 0, period_target = 0))

        p <- ggplot(plot_data, aes(x = reorder(Entity, amount), y = amount)) +
            geom_segment(
                aes(xend = Entity, y = 0, yend = amount),
                color = "#BDBDBD",
                linewidth = 1.2
            ) +
            geom_point(aes(color = "Actual Received"), size = 5) +
            geom_point(
                aes(y = period_target, color = "Period Target"),
                shape = 18,
                size = 6
            ) +
            scale_color_manual(
                values = c(
                    "Actual Received" = "#2E7D32",
                    "Period Target" = "#D32F2F"
                )
            ) +
            scale_y_continuous(labels = comma_format) + # <--- FIX APPLIED
            coord_flip() +
            labs(
                title = "Total Church Assessment Performance vs Target",
                x = NULL,
                y = "Amount (KSh)",
                color = NULL
            ) +
            theme_minimal() +
            theme(
                text = element_text(family = "sans"),
                plot.title = element_text(face = "bold", size = 12),
                legend.position = "bottom"
            )

        ggsave(
            paste0(plot_dir, "assessment_income_church_trend.png"),
            plot = p,
            width = 12,
            height = 6,
            dpi = 300
        )
        cat("✅ Saved assessment_income_church_trend.png\n")
    }
}

# --- PLOT 4: Assessment Expenditure Variance Chart ---
save_assessment_expenditure_bars <- function(df, s_date, e_date, t_df) {
    num_months <- interval(s_date, e_date) %/% months(1) + 1
    by_quarter <- num_months >= 6
    labels <- get_time_labels(s_date, e_date, by_quarter)

    exp_targets <- t_df %>%
        filter(
            grepl("Assessment", category, ignore.case = TRUE) &
                category != "Assessment_Income"
        )
    target_val <- if (nrow(exp_targets) > 0) {
        exp_targets$monthly_target[1]
    } else {
        0
    }
    if (by_quarter) {
        target_val <- target_val * 3
    }

    actuals <- df %>%
        filter(
            date >= s_date,
            date <= e_date,
            grepl("Assessment", category, ignore.case = TRUE),
            transaction_type == "Expense"
        )

    if (by_quarter) {
        q_map <- c(
            "1" = "Jan-Mar",
            "2" = "Apr-Jun",
            "3" = "Jul-Sep",
            "4" = "Oct-Dec"
        )
        actuals <- actuals %>%
            mutate(
                label = paste(q_map[as.character(quarter(date))], year(date))
            )
    } else {
        actuals <- actuals %>% mutate(label = format(date, "%b %Y"))
    }

    actual_sum <- actuals %>%
        group_by(label) %>%
        summarise(amount = sum(amount), .groups = 'drop')

    plot_data <- tibble(label = labels, target = target_val) %>%
        left_join(actual_sum, by = "label") %>%
        replace_na(list(amount = 0)) %>%
        mutate(
            variance = amount - target,
            status = if_else(variance >= 0, "Target Met/Overpaid", "Shortfall"),
            label = factor(label, levels = labels)
        )

    p <- ggplot(plot_data, aes(x = label, y = variance, fill = status)) +
        geom_hline(yintercept = 0, color = "black", linewidth = 0.8) +
        geom_col(width = 0.5) +
        scale_fill_manual(
            values = c(
                "Target Met/Overpaid" = "#4CAF50",
                "Shortfall" = "#D32F2F"
            )
        ) +
        scale_y_continuous(labels = comma_format) + # <--- FIX APPLIED
        labs(
            title = paste(
                "Assessment Expenditure Variance",
                ifelse(by_quarter, "(Quarterly)", "(Monthly)")
            ),
            subtitle = paste(
                "Baseline (0) = Synod Target of",
                format(target_val, big.mark = ",")
            ),
            x = NULL,
            y = "Variance Amount (KSh)",
            fill = NULL
        ) +
        theme_minimal() +
        theme(
            text = element_text(family = "sans"),
            plot.title = element_text(face = "bold", size = 12),
            legend.position = "bottom"
        )

    ggsave(
        paste0(plot_dir, "assessment_perf.png"),
        plot = p,
        width = 10,
        height = 5,
        dpi = 300
    )
    cat("✅ Saved assessment_perf.png\n")
}

# --- PLOT 5: Faceted Small Multiples for Stipends ---
save_minister_stipend_bars <- function(df, s_date, e_date, t_df) {
    labels <- get_time_labels(s_date, e_date, by_quarter = FALSE)

    stipend_targets <- t_df %>%
        filter(grepl("Stipend", category, ignore.case = TRUE))
    actuals <- df %>%
        filter(date >= s_date, date <= e_date, category == "Stipend") %>%
        mutate(label = format(date, "%b %Y"))

    if (nrow(actuals) > 0 && nrow(stipend_targets) > 0) {
        actual_sum <- actuals %>%
            group_by(label, description) %>%
            summarise(amount = sum(amount), .groups = 'drop')

        valid_ministers <- unique(stipend_targets$Entity)
        plot_data <- expand_grid(label = labels, Entity = valid_ministers) %>%
            left_join(actual_sum, by = c("label", "Entity" = "description")) %>%
            left_join(
                stipend_targets %>% select(Entity, target = monthly_target),
                by = "Entity"
            ) %>%
            replace_na(list(amount = 0, target = 0)) %>%
            mutate(label = factor(label, levels = labels))

        p <- ggplot(plot_data, aes(x = label, y = amount, fill = Entity)) +
            geom_col(width = 0.6, show.legend = FALSE) +
            geom_hline(
                aes(yintercept = target, color = "Target"),
                linetype = "dashed",
                linewidth = 1
            ) +
            scale_fill_manual(
                values = c("#DAA520", "#4682B4", "#2E8B57", "#8E24AA")
            ) +
            scale_color_manual(name = NULL, values = c("Target" = "#D32F2F")) +
            scale_y_continuous(labels = comma_format) + # <--- FIX APPLIED
            facet_wrap(~Entity, ncol = 1, scales = "free_y") +
            labs(
                title = "Ministerial Stipend Fulfillment",
                x = NULL,
                y = "Amount (KSh)"
            ) +
            theme_minimal() +
            theme(
                text = element_text(family = "sans"),
                plot.title = element_text(face = "bold", size = 12),
                axis.text.x = element_text(angle = 45, hjust = 1),
                strip.text = element_text(face = "bold", size = 11),
                legend.position = "top"
            )

        ggsave(
            paste0(plot_dir, "stipend_perf.png"),
            plot = p,
            width = 10,
            height = 6,
            dpi = 300
        )
        cat("✅ Saved stipend_perf.png\n")
    }
}

# 3. Execute Plotting Functions
save_trend_bars(
    ledger_df,
    start_date,
    end_date,
    "Assessment Received",
    "Assessment Income",
    "assessment_income_trend.png"
)
save_trend_bars(
    ledger_df,
    start_date,
    end_date,
    "Offertory",
    "Offertory Income",
    "offertory_income_trend.png"
)
save_assessment_church_target_bars(ledger_df, start_date, end_date, targets_df)
save_assessment_expenditure_bars(ledger_df, start_date, end_date, targets_df)
save_minister_stipend_bars(ledger_df, start_date, end_date, targets_df)

cat("🎉 R Plotter Phase Complete.\n")
