import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


SOURCE = Path(r"C:\Users\Windows 11\Desktop\Projeto-Fluxo-WDO-WIN\dados_parquet")
SAMPLE_ROOT = Path(r"C:\Users\Windows 11\Documents\Codex\2026-08-04\considerando-que-voc-um-trader-autonomo-2\work\transfer_sample_v1")
MANIFEST_PATH = Path(r"C:\Users\Windows 11\Documents\Codex\2026-08-04\considerando-que-voc-um-trader-autonomo-2\outputs\transfer-sample-v1-manifest.json")
ROWS = 100_000

SELECTIONS = [
    ("wdofut", "legacy_2026-03", "ticker=wdofut/ano=2026/mes=03/data_0.parquet"),
    ("wdofut", "recent_2026-04", "ticker=wdofut/ano=2026/mes=04/data_0.parquet"),
    ("winfut", "legacy_2026-03", "ticker=winfut/ano=2026/mes=03/data_0.parquet"),
    ("winfut", "recent_2026-04", "ticker=winfut/ano=2026/mes=04/data_0.parquet"),
]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


SAMPLE_ROOT.mkdir(parents=True, exist_ok=True)
entries = []

for ticker, label, relative_source in SELECTIONS:
    source = SOURCE / Path(relative_source)
    output = SAMPLE_ROOT / ticker / f"{label}.parquet"
    output.parent.mkdir(parents=True, exist_ok=True)

    parquet = pq.ParquetFile(source)
    batch = next(parquet.iter_batches(batch_size=ROWS))
    table = pa.Table.from_batches([batch])
    pq.write_table(table, output, compression="zstd")

    entries.append(
        {
            "ticker": ticker,
            "label": label,
            "source_relative_path": relative_source,
            "source_rows": parquet.metadata.num_rows,
            "sample_rows": table.num_rows,
            "sample_relative_path": output.relative_to(SAMPLE_ROOT).as_posix(),
            "sample_bytes": output.stat().st_size,
            "sample_sha256": sha256(output),
            "schema": [(field.name, str(field.type)) for field in table.schema],
        }
    )

manifest = {
    "sample_id": "transfer_sample_v1",
    "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "source_root": str(SOURCE),
    "sample_root": str(SAMPLE_ROOT),
    "rows_per_file": ROWS,
    "entries": entries,
    "purpose": "Validate transfer, permissions, Parquet reading and schema handling before full migration.",
    "originals_unchanged": True,
}
MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(manifest, ensure_ascii=False, indent=2))
