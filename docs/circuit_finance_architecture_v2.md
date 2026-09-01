# Circuit finance architecture — v2 (containerized)

Reflects the actual current stack: Docker containers for NocoDB, the three-stage report
pipeline, and the Shiny dashboard. Paste into `docs/architecture.md`.

```mermaid
flowchart TB
    Treasurers["Treasurers"]
    Viewers["Viewers"]
    EmailRecipients["Email recipients"]

    subgraph HomeServer["Home server — Docker containers + Tailscale"]
        NocoDB["NocoDB<br/><small>data entry UI</small>"]
        Postgres["Postgres<br/><small>structured tables</small>"]

        subgraph Pipeline["Report pipeline — sequential, one-shot"]
            PythonLedger["python-ledger<br/><small>reads Postgres</small>"]
            RPlotter["r-plotter<br/><small>renders charts</small>"]
            LatexBuilder["latex-builder<br/><small>builds PDF</small>"]
        end

        ShinyDashboard["circuit-dashboard<br/><small>live charts, ledger</small>"]
    end

    Treasurers -->|via Tailscale| NocoDB
    NocoDB --> Postgres
    Postgres --> PythonLedger
    PythonLedger --> RPlotter
    RPlotter --> LatexBuilder
    Postgres --> ShinyDashboard
    LatexBuilder -->|quarterly PDF| EmailRecipients
    ShinyDashboard -->|live view| Viewers

    classDef server fill:#F1EFE8,stroke:#5F5E5A,color:#444441
    classDef db fill:#E1F5EE,stroke:#0F6E56,color:#085041
    classDef app fill:#E6F1FB,stroke:#185FA5,color:#0C447C
    classDef pipeline fill:#EEEDFE,stroke:#534AB7,color:#3C3489
    classDef dashboard fill:#FBEAF0,stroke:#993556,color:#72243E
    classDef person fill:#FAECE7,stroke:#993C1D,color:#712B13

    class HomeServer,Pipeline server
    class Postgres db
    class NocoDB app
    class PythonLedger,RPlotter,LatexBuilder pipeline
    class ShinyDashboard dashboard
    class Treasurers,Viewers,EmailRecipients person
```

## What changed from v1

- **NocoDB** now runs as its own container (`circuit_nocodb`), talking to Postgres over
  `host.docker.internal`.
- **Report script** is now three chained one-shot containers, not one script — python-ledger
  exports data, r-plotter renders charts from it, latex-builder assembles the final PDF.
  Run sequentially via a shell script, not `docker compose up` together, since each stage
  depends on the previous one's output.
- **Shiny dashboard** (`circuit-dashboard`) is new — reads Postgres independently of the
  report pipeline, serving a live, always-available view rather than a scheduled snapshot.
- **Tailscale Serve** fronts multiple services now (NocoDB, the dashboard) with clean paths
  under one hostname, rather than raw IP:port per service.
