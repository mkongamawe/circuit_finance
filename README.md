# Circuit Finance

This repo contains the work/scripts required to set up a church finance automated system.
It contains the scripts to set up the necessary containers and pipeline. It does however does not contain the codes required to set up the daemon and also the database itself.

## Repo structure

```bash
> tree -a
.
├── data
│   └── logo
│       ├── crc.jpeg
│       ├── mck.jpeg
│       └── wmc.png
├── docker_directory
│   ├── app
│   │   └── app.R
│   ├── data
│   │   └── logo
│   │       ├── crc.jpeg
│   │       ├── mck.jpeg
│   │       └── wmc.png
│   ├── docker-compose.yml
│   ├── Dockerfile.latex-builder
│   ├── Dockerfile.python-ledger
│   ├── Dockerfile.r-plotter
│   ├── Dockerfile.r-shiny
│   ├── run_docker_pipeline.sh
│   ├── scripts
│   │   ├── bash
│   │   │   ├── entrypoint.sh
│   │   │   └── write-renviron.sh
│   │   ├── python
│   │   │   ├── autobot.py
│   │   │   ├── latex_builder.py
│   │   │   ├── python_ledger.py
│   │   │   └── send_report.py
│   │   └── r
│   │       └── plotter.R
│   └── templates
│       └── church_report_template.tex
├── docs
│   └── schema.md
├── generate_report.sh
├── README.md
├── scripts
│   ├── python
│   │   ├── autobot.py
│   │   ├── run_report.py
│   │   └── send_report.py
│   └── sql
│       ├── helpful_script.sql
│       └── schema.sql
└── templates
    └── church_report_template.tex

17 directories, 30 files
```
