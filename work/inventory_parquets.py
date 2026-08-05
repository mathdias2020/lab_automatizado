import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import pyarrow.parquet as pq


SOURCE = Path(r"C:\Users\Windows 11\Desktop\Projeto-Fluxo-WDO-WIN\dados_parquet")
OUTPUT_DIR = Path(r"C:\Users\Windows 11\Documents\Codex\2026-08-04\considerando-que-voc-um-trader-autonomo-2\outputs")
OUTPUT_JSON = OUTPUT_DIR / "parquet-inventory-2026-08-05.json"
OUTPUT_MD = OUTPUT_DIR / "parquet-inventory-2026-08-05.md"


def expected_months(start_year=2012, start_month=4, end_year=2026, end_month=6):
    result = []
    year, month = start_year, start_month
    while (year, month) <= (end_year, end_month):
        result.append(f"{year:04d}-{month:02d}")
        month += 1
        if month == 13:
            year += 1
            month = 1
    return result


def schema_variant(fields):
    names = [name for name, _, _ in fields]
    types = {name: typ for name, typ, _ in fields}
    if "date" in names and "time" in names and types.get("buy_agent") == "string":
        return "legacy_date_time_named_agents"
    if "ts" in names and types.get("buy_agent") == "int32":
        return "event_ts_numeric_agents"
    return "other"


def format_bytes(value):
    value = float(value)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.2f} {unit}"
        value /= 1024


files = sorted(SOURCE.rglob("*.parquet"))
by_ticker = defaultdict(
    lambda: {
        "files": 0,
        "bytes": 0,
        "rows": 0,
        "row_groups": 0,
        "months": set(),
        "schema_variants": Counter(),
        "variant_files": defaultdict(list),
    }
)
file_entries = []
schema_definitions = {}

for path in files:
    relative = path.relative_to(SOURCE).as_posix()
    partition_values = {}
    for part in Path(relative).parts[:-1]:
        if "=" in part:
            key, value = part.split("=", 1)
            partition_values[key] = value

    ticker = partition_values.get("ticker", "unknown")
    period = f"{partition_values.get('ano', 'unknown')}-{partition_values.get('mes', 'unknown')}"
    parquet = pq.ParquetFile(path)
    fields = [(field.name, str(field.type), field.nullable) for field in parquet.schema_arrow]
    variant = schema_variant(fields)
    signature = json.dumps(fields, ensure_ascii=False)
    schema_definitions.setdefault(variant, {"fields": fields, "signature": signature})

    entry = {
        "relative_path": relative,
        "ticker": ticker,
        "period": period,
        "bytes": path.stat().st_size,
        "rows": parquet.metadata.num_rows,
        "row_groups": parquet.metadata.num_row_groups,
        "schema_variant": variant,
        "sha256": None,
        "hash_status": "not_computed",
    }
    file_entries.append(entry)

    aggregate = by_ticker[ticker]
    aggregate["files"] += 1
    aggregate["bytes"] += entry["bytes"]
    aggregate["rows"] += entry["rows"]
    aggregate["row_groups"] += entry["row_groups"]
    aggregate["months"].add(period)
    aggregate["schema_variants"][variant] += 1
    aggregate["variant_files"][variant].append(relative)

expected = set(expected_months())
summary = {}
for ticker, aggregate in sorted(by_ticker.items()):
    months = sorted(aggregate["months"])
    summary[ticker] = {
        "files": aggregate["files"],
        "bytes": aggregate["bytes"],
        "bytes_human": format_bytes(aggregate["bytes"]),
        "rows": aggregate["rows"],
        "row_groups": aggregate["row_groups"],
        "period_first": months[0] if months else None,
        "period_last": months[-1] if months else None,
        "month_count": len(months),
        "missing_months_in_2012_04_to_2026_06": sorted(expected - aggregate["months"]),
        "schema_variants": dict(aggregate["schema_variants"]),
        "variant_files": {
            variant: sorted(paths)
            for variant, paths in aggregate["variant_files"].items()
        },
    }

inventory = {
    "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "source": str(SOURCE),
    "parquet_count": len(files),
    "total_bytes": sum(entry["bytes"] for entry in file_entries),
    "total_bytes_human": format_bytes(sum(entry["bytes"] for entry in file_entries)),
    "hash_policy": "Hashes are pending and must be computed for the selected transfer snapshot before upload.",
    "by_ticker": summary,
    "schema_definitions": schema_definitions,
    "files": file_entries,
    "warnings": [
        "WDOFUT is missing the partition 2017-06.",
        "WDOFUT and WINFUT use a second schema for 2026-04 through 2026-06.",
        "The raw dataset should not be uploaded as one canonical table until the schema transition is explicitly handled.",
        "The full raw dataset is approximately 76.59 GB and leaves limited room on the 100 GB VPS for derived DuckDBs and temporary artifacts.",
    ],
}

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_JSON.write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding="utf-8")

lines = [
    "# Inventário dos Parquets",
    "",
    f"- Gerado em UTC: {inventory['generated_at_utc']}",
    f"- Origem: {SOURCE}",
    f"- Arquivos: {inventory['parquet_count']}",
    f"- Tamanho total: {inventory['total_bytes_human']}",
    "",
    "## Resumo por ativo",
    "",
    "| Ativo | Arquivos | Linhas | Tamanho | Período | Meses ausentes | Schemas |",
    "|---|---:|---:|---:|---|---|---|",
]
for ticker, data in summary.items():
    missing = ", ".join(data["missing_months_in_2012_04_to_2026_06"]) or "nenhum"
    schemas = ", ".join(f"{name}: {count}" for name, count in data["schema_variants"].items())
    lines.append(
        f"| {ticker} | {data['files']} | {data['rows']:,} | {data['bytes_human']} | "
        f"{data['period_first']} a {data['period_last']} | {missing} | {schemas} |"
    )

lines.extend(
    [
        "",
        "## Variantes de schema",
        "",
        "### legacy_date_time_named_agents",
        "",
        "Campos históricos com date, time, qty, vol e nomes textuais de agentes.",
        "",
        "### event_ts_numeric_agents",
        "",
        "Campos recentes com ts, quantity, volume, IDs numéricos de agentes e is_edit.",
        "",
        "## Arquivos com schema recente",
        "",
    ]
)
for ticker, data in summary.items():
    for variant, paths in data["variant_files"].items():
        if variant != "legacy_date_time_named_agents":
            lines.append(f"### {ticker} — {variant}")
            lines.extend(f"- {path}" for path in paths)
            lines.append("")

lines.extend(
    [
        "## Alertas",
        "",
        "- O WDOFUT não possui a partição 2017-06.",
        "- WDOFUT e WINFUT mudam de schema entre março e abril de 2026.",
        "- O dataset completo não deve ser transferido antes de decidirmos se a normalização ocorrerá na origem, na leitura ou em uma camada derivada.",
        "- O tamanho bruto de aproximadamente 76,59 GB deixa pouca folga na KVM2 para DuckDBs, artefatos e temporários.",
        "",
        "## Próxima decisão",
        "",
        "Escolher a estratégia de compatibilização dos dois schemas e selecionar uma amostra pequena de cada ativo e variante para transferência e validação.",
    ]
)
OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(OUTPUT_JSON)
print(OUTPUT_MD)
