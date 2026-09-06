####################################################################
# Circuit Finance Dashboard
#
# Reads from the `general_ledger` and `account_balances` views, plus
# `transactions`/`funds`/`categories` for the fund breakdown. Talks to
# Postgres via a read-only role (see README for the GRANT statements).
####################################################################

library(shiny)
library(shinydashboard)
library(fresh)
library(DBI)
library(RPostgres)
library(dplyr)
library(DT)
library(plotly)
library(lubridate)
library(scales)

## ---- CONFIG ---------------------------------------------------------
DB_HOST <- Sys.getenv("CIRCUIT_DB_HOST", "localhost")
DB_PORT <- as.integer(Sys.getenv("CIRCUIT_DB_PORT", "5432"))
DB_NAME <- Sys.getenv("CIRCUIT_DB_NAME", "circuit_finance_prod")
message("DEBUG — DB resolved to: ", DB_NAME, " | DB_NAME: ", DB_NAME)
DB_USER <- Sys.getenv("CIRCUIT_DB_USER", "shiny_reader")
DB_PASS <- Sys.getenv("CIRCUIT_DB_PASS")
if (DB_PASS == "") {
    stop("CIRCUIT_DB_PASS is not set — check .env / env_file configuration.")
}

## ---- THEME (fresh) ---------------------------------------------------
my_theme <- create_theme(
    adminlte_color(
        light_blue = "#2C3E50", # sidebar / header
        green = "#2E8B57", # income
        red = "#B33A3A", # expense
        blue = "#3B6E9E", # neutral / net
        orange = "#D98E04" # restricted funds
    ),
    adminlte_sidebar(
        dark_bg = "#1F2B38",
        dark_hover_bg = "#2C3E50",
        dark_color = "#ECF0F1"
    ),
    adminlte_global(
        content_bg = "#F4F6F7",
        box_bg = "#FFFFFF",
        info_box_bg = "#FFFFFF"
    )
)

## ---- DATA LOADING ------------------------------------------------------
# One connection per refresh, closed immediately after — fine for a
# low-traffic single-user dashboard.

load_data <- function() {
    con <- dbConnect(
        RPostgres::Postgres(),
        host = DB_HOST,
        port = DB_PORT,
        dbname = DB_NAME,
        user = DB_USER,
        password = DB_PASS
    )
    on.exit(dbDisconnect(con))

    ledger <- dbGetQuery(
        con,
        "
    SELECT
      gl.*,
      CASE
        WHEN gl.entry_type = 'transaction' THEN EXISTS (
          SELECT 1 FROM transactions vr WHERE vr.voided_tx_id = gl.id
        )
        WHEN gl.entry_type = 'transfer' THEN EXISTS (
          SELECT 1 FROM transfers vr WHERE vr.voided_tx_id = gl.id
        )
        ELSE FALSE
      END AS is_voided
    FROM general_ledger gl
    "
    ) |>
        mutate(
            entry_date = as.Date(entry_date),
            flow = case_when(
                category_type == "income" ~ "income",
                category_type == "expense" ~ "expense",
                TRUE ~ "transfer"
            )
        )

    balances <- dbGetQuery(con, "SELECT * FROM account_balances")

    # Reporting data excludes both sides of a voided transaction:
    # the original row and its negative reversal row. This follows
    # schema_new.sql, where voiding is represented by voided_tx_id
    # rather than an is_voided column.
    reporting_ledger <- dbGetQuery(
        con,
        "
    SELECT
      t.id,
      t.transaction_date AS entry_date,
      a.name AS account_name,
      c.name AS category_name,
      c.category_type,
      f.name AS fund_name,
      ch.name AS church_name,
      m.screen_name AS minister_name,
      CASE WHEN c.category_type = 'income' THEN t.amount ELSE -t.amount END AS signed_amount,
      t.description,
      u.full_name AS entered_by_name,
      (t.voided_tx_id IS NOT NULL) AS is_reversal,
      'transaction' AS entry_type
    FROM transactions t
    JOIN accounts a ON a.id = t.account_id
    JOIN categories c ON c.id = t.category_id
    LEFT JOIN funds f ON f.id = t.fund_id
    LEFT JOIN churches ch ON ch.id = t.church_id
    LEFT JOIN ministers m ON m.id = t.minister_id
    JOIN users u ON u.id = t.entered_by
    WHERE t.voided_tx_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM transactions vr
        WHERE vr.voided_tx_id = t.id
      )
    "
    ) |>
        mutate(
            entry_date = as.Date(entry_date),
            flow = case_when(
                category_type == "income" ~ "income",
                category_type == "expense" ~ "expense",
                TRUE ~ "transfer"
            )
        )

    funds <- dbGetQuery(
        con,
        "
    SELECT
      f.name AS fund,
      f.is_restricted,
      c.category_type,
      t.transaction_date,
      t.amount
    FROM transactions t
    JOIN categories c ON c.id = t.category_id
    JOIN funds f ON f.id = t.fund_id
    WHERE t.voided_tx_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM transactions vr
        WHERE vr.voided_tx_id = t.id
      )
    "
    ) |>
        mutate(transaction_date = as.Date(transaction_date))

    list(
        ledger = ledger,
        reporting_ledger = reporting_ledger,
        balances = balances,
        funds = funds
    )
}

## ---- UI ------------------------------------------------------------------

ui <- dashboardPage(
    dashboardHeader(title = "Circuit Finance"),

    dashboardSidebar(
        sidebarMenu(
            menuItem(
                "Overview",
                tabName = "overview",
                icon = icon("gauge-high")
            ),
            menuItem("General Ledger", tabName = "ledger", icon = icon("book")),
            menuItem("Funds", tabName = "funds", icon = icon("layer-group")),
            menuItem(
                "Assessments",
                tabName = "assessments",
                icon = icon("church")
            )
        ),
        dateRangeInput(
            "date_range",
            "Date range",
            start = floor_date(Sys.Date() - years(1), "year"),
            end = Sys.Date()
        ),
        actionButton(
            "refresh",
            "Refresh data",
            icon = icon("rotate"),
            style = "margin-left:15px;"
        )
    ),

    dashboardBody(
        use_theme(my_theme),
        tags$head(tags$style(HTML(
            "
      .box { border-top: 3px solid #2C3E50; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .small-box { box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .btn-download-pretty {
        background: linear-gradient(135deg, #2E8B57, #3B6E9E);
        color: #ffffff !important;
        border: none;
        border-radius: 999px;
        padding: 7px 18px;
        font-weight: 600;
        font-size: 13px;
        letter-spacing: 0.2px;
        box-shadow: 0 2px 6px rgba(0,0,0,0.15);
        transition: transform 0.15s ease, box-shadow 0.15s ease, opacity 0.15s ease;
      }
      .btn-download-pretty:hover {
        transform: translateY(-1px);
        box-shadow: 0 4px 10px rgba(0,0,0,0.2);
        color: #ffffff !important;
        opacity: 0.95;
      }
      .download-row {
        text-align: right;
        margin-bottom: 12px;
      }
    "
        ))),

        tabItems(
            ## ---- OVERVIEW ----
            tabItem(
                tabName = "overview",
                fluidRow(uiOutput("balance_boxes")),
                div(
                    class = "download-row",
                    downloadButton(
                        "download_overview",
                        "Download overview data",
                        icon = icon("download"),
                        class = "btn-download-pretty"
                    )
                ),
                fluidRow(
                    valueBoxOutput("total_income"),
                    valueBoxOutput("total_expense"),
                    valueBoxOutput("net_balance")
                ),
                fluidRow(
                    tabBox(
                        width = 12,
                        height = "480px",
                        tabPanel(
                            "Monthly Income Vs Expense",
                            plotlyOutput("monthly_chart", height = "480px")
                        ),
                        tabPanel(
                            "Expenses by Category",
                            plotlyOutput("category_chart", height = "480px")
                        )
                    )
                )
            ),

            ## ---- GENERAL LEDGER ----
            tabItem(
                tabName = "ledger",
                box(
                    width = 12,
                    status = "primary",
                    title = "General Ledger",
                    checkboxInput(
                        "show_voided",
                        "Show voided entries",
                        value = FALSE
                    ),
                    div(
                        class = "download-row",
                        downloadButton(
                            "download_ledger",
                            "Download ledger",
                            icon = icon("download"),
                            class = "btn-download-pretty"
                        )
                    ),
                    DTOutput("ledger_table")
                )
            ),

            ## ---- FUNDS ----
            tabItem(
                tabName = "funds",
                fluidRow(
                    box(
                        title = "Income vs Expense by Fund",
                        width = 8,
                        status = "primary",
                        div(
                            class = "download-row",
                            downloadButton(
                                "download_funds",
                                "Download fund data",
                                icon = icon("download"),
                                class = "btn-download-pretty"
                            )
                        ),
                        plotlyOutput("fund_chart")
                    ),
                    box(
                        title = "Restricted Funds",
                        width = 4,
                        status = "warning",
                        tableOutput("restricted_funds_table")
                    )
                )
            ),

            ## ---- ASSESSMENTS ----
            tabItem(
                tabName = "assessments",
                box(
                    width = 12,
                    status = "primary",
                    title = "Monthly Assessment Received by Church",
                    div(
                        class = "download-row",
                        downloadButton(
                            "download_assessments",
                            "Download assessment data",
                            icon = icon("download"),
                            class = "btn-download-pretty"
                        )
                    ),
                    plotlyOutput("assessment_chart", height = "500px")
                )
            )
        )
    )
)

## ---- SERVER ----------------------------------------------------------------

server <- function(input, output, session) {
    raw <- reactiveVal(load_data())
    observeEvent(input$refresh, raw(load_data()))

    ledger_in_range <- reactive({
        df <- raw()$ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2]
            )
        if (!isTRUE(input$show_voided)) {
            # Hide both the original entry that was voided and its reversal.
            df <- df |> filter(!is_voided, !is_reversal)
        }
        df
    })

    ## ---- Account balance icon boxes ----
    output$balance_boxes <- renderUI({
        bal <- raw()$balances
        boxes <- lapply(seq_len(nrow(bal)), function(i) {
            row <- bal[i, ]
            valueBox(
                dollar(row$current_balance, prefix = "KES "),
                subtitle = row$account_name,
                icon = icon(
                    if (
                        grepl(
                            "M-Pesa|Petty",
                            row$account_name,
                            ignore.case = TRUE
                        )
                    ) {
                        "mobile-screen"
                    } else {
                        "building-columns"
                    }
                ),
                color = if (row$current_balance >= 0) "blue" else "red",
                width = 3
            )
        })
        do.call(fluidRow, boxes)
    })

    ## ---- Value boxes (income/expense/net, transactions only) ----
    output$total_income <- renderValueBox({
        v <- raw()$reporting_ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2],
                flow == "income"
            ) |>
            pull(signed_amount) |>
            sum(na.rm = TRUE)
        valueBox(
            dollar(v, prefix = "KES "),
            "Total Income",
            icon = icon("arrow-up"),
            color = "green"
        )
    })

    output$total_expense <- renderValueBox({
        v <- raw()$reporting_ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2],
                flow == "expense"
            ) |>
            pull(signed_amount) |>
            sum(na.rm = TRUE) |>
            abs()
        valueBox(
            dollar(v, prefix = "KES "),
            "Total Expenses",
            icon = icon("arrow-down"),
            color = "red"
        )
    })

    output$net_balance <- renderValueBox({
        v <- raw()$reporting_ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2]
            ) |>
            pull(signed_amount) |>
            sum(na.rm = TRUE)
        valueBox(
            dollar(v, prefix = "KES "),
            "Net (period)",
            icon = icon("scale-balanced"),
            color = if (v >= 0) "blue" else "orange"
        )
    })

    ## ---- Monthly income vs expense ----
    output$monthly_chart <- renderPlotly({
        monthly <- raw()$reporting_ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2]
            ) |>
            mutate(month = floor_date(entry_date, "month")) |>
            group_by(month, flow) |>
            summarise(total = sum(abs(signed_amount)), .groups = "drop")

        p <- ggplot2::ggplot(
            monthly,
            ggplot2::aes(x = month, y = total, fill = flow)
        ) +
            ggplot2::geom_col(position = "dodge") +
            ggplot2::scale_fill_manual(
                values = c(income = "#2E8B57", expense = "#B33A3A")
            ) +
            ggplot2::scale_y_continuous(labels = function(x) {
                dollar(x, prefix = "KES ")
            }) +
            ggplot2::labs(x = NULL, y = NULL, fill = NULL) +
            ggplot2::theme_minimal(base_size = 12)

        ggplotly(p)
    })

    ## ---- Category breakdown (expenses only) ----
    output$category_chart <- renderPlotly({
        by_cat <- raw()$reporting_ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2],
                flow == "expense"
            ) |>
            group_by(category_name) |>
            summarise(total = sum(abs(signed_amount)), .groups = "drop") |>
            arrange(desc(total))

        plot_ly(
            by_cat,
            labels = ~category_name,
            values = ~total,
            type = "pie",
            marker = list(
                colors = colorRampPalette(c(
                    "#2C3E50",
                    "#B33A3A",
                    "#D98E04"
                ))(nrow(
                    by_cat
                ))
            ),
            textinfo = "label+percent"
        ) |>
            layout(showlegend = FALSE)
    })

    ## ---- General ledger table ----
    output$ledger_table <- renderDT({
        ledger_in_range() |>
            select(
                entry_date,
                entry_type,
                account_name,
                category_name,
                church_name,
                minister_name,
                signed_amount,
                description,
                entered_by_name,
                is_reversal
            ) |>
            arrange(desc(entry_date)) |>
            datatable(
                filter = "top",
                options = list(pageLength = 20),
                rownames = FALSE
            ) |>
            formatCurrency("signed_amount", currency = "KES ")
    })

    ## ---- Funds tab ----
    output$fund_chart <- renderPlotly({
        fd <- raw()$funds |>
            filter(
                transaction_date >= input$date_range[1],
                transaction_date <= input$date_range[2]
            ) |>
            group_by(fund, category_type) |>
            summarise(total = sum(amount), .groups = "drop")

        p <- ggplot2::ggplot(
            fd,
            ggplot2::aes(x = fund, y = total, fill = category_type)
        ) +
            ggplot2::geom_col(position = "dodge") +
            ggplot2::scale_fill_manual(
                values = c(income = "#2E8B57", expense = "#B33A3A")
            ) +
            ggplot2::scale_y_continuous(labels = function(x) {
                dollar(x, prefix = "KES ")
            }) +
            ggplot2::labs(x = NULL, y = NULL, fill = NULL) +
            ggplot2::theme_minimal(base_size = 12) +
            ggplot2::theme(
                axis.text.x = ggplot2::element_text(angle = 30, hjust = 1)
            )

        ggplotly(p)
    })

    ## ---- Monthly assessment received, by church ----
    output$assessment_chart <- renderPlotly({
        church_assessment <- raw()$reporting_ledger |>
            filter(
                entry_date >= input$date_range[1],
                entry_date <= input$date_range[2],
                category_name == "Assessment Received"
            ) |>
            mutate(month = floor_date(entry_date, "month")) |>
            group_by(month, church_name) |>
            summarise(total = sum(signed_amount), .groups = "drop")

        # Generate one color per church from your brand palette so this
        # chart matches the rest of the dashboard, regardless of how many
        # churches you have.
        n_churches <- n_distinct(church_assessment$church_name)
        church_palette <- colorRampPalette(c(
            "#2C3E50",
            "#3B6E9E",
            "#2E8B57",
            "#D98E04",
            "#B33A3A"
        ))(n_churches)

        p <- ggplot2::ggplot(
            church_assessment,
            ggplot2::aes(x = month, y = total, fill = church_name)
        ) +
            ggplot2::geom_col(position = "dodge") +
            ggplot2::scale_fill_manual(values = church_palette) +
            ggplot2::scale_y_continuous(labels = function(x) {
                dollar(x, prefix = "KES ")
            }) +
            ggplot2::labs(x = NULL, y = NULL, fill = "Church") +
            ggplot2::theme_minimal(base_size = 12)

        ggplotly(p)
    })

    ## ---- Downloads ------------------------------------------------------
    output$download_overview <- downloadHandler(
        filename = function() paste0("circuit_overview_", Sys.Date(), ".csv"),
        content = function(file) {
            raw()$reporting_ledger |>
                filter(
                    entry_date >= input$date_range[1],
                    entry_date <= input$date_range[2]
                ) |>
                select(
                    entry_date,
                    account_name,
                    category_name,
                    category_type,
                    fund_name,
                    church_name,
                    minister_name,
                    signed_amount,
                    flow,
                    description,
                    entered_by_name
                ) |>
                arrange(desc(entry_date)) |>
                write.csv(file, row.names = FALSE, na = "")
        },
        contentType = "text/csv"
    )

    output$download_ledger <- downloadHandler(
        filename = function() {
            paste0("circuit_general_ledger_", Sys.Date(), ".csv")
        },
        content = function(file) {
            ledger_in_range() |>
                select(
                    entry_date,
                    entry_type,
                    account_name,
                    category_name,
                    category_type,
                    fund_name,
                    church_name,
                    minister_name,
                    signed_amount,
                    description,
                    entered_by_name,
                    is_reversal,
                    voids_entry_date,
                    voided_reason
                ) |>
                arrange(desc(entry_date)) |>
                write.csv(file, row.names = FALSE, na = "")
        },
        contentType = "text/csv"
    )

    output$download_funds <- downloadHandler(
        filename = function() paste0("circuit_funds_", Sys.Date(), ".csv"),
        content = function(file) {
            raw()$funds |>
                filter(
                    transaction_date >= input$date_range[1],
                    transaction_date <= input$date_range[2]
                ) |>
                group_by(fund, is_restricted, category_type) |>
                summarise(
                    total = sum(amount, na.rm = TRUE),
                    .groups = "drop"
                ) |>
                arrange(fund, category_type) |>
                write.csv(file, row.names = FALSE, na = "")
        },
        contentType = "text/csv"
    )

    output$download_assessments <- downloadHandler(
        filename = function() {
            paste0("circuit_assessments_", Sys.Date(), ".csv")
        },
        content = function(file) {
            raw()$reporting_ledger |>
                filter(
                    entry_date >= input$date_range[1],
                    entry_date <= input$date_range[2],
                    category_name == "Assessment Received"
                ) |>
                mutate(month = floor_date(entry_date, "month")) |>
                group_by(month, church_name) |>
                summarise(
                    total = sum(signed_amount, na.rm = TRUE),
                    .groups = "drop"
                ) |>
                arrange(month, church_name) |>
                write.csv(file, row.names = FALSE, na = "")
        },
        contentType = "text/csv"
    )

    output$restricted_funds_table <- renderTable(
        {
            raw()$funds |>
                filter(is_restricted) |>
                group_by(fund) |>
                summarise(
                    income = sum(amount[category_type == "income"]),
                    expense = sum(amount[category_type == "expense"]),
                    balance = income - expense,
                    .groups = "drop"
                )
        },
        digits = 0
    )
}

shinyApp(ui, server)
