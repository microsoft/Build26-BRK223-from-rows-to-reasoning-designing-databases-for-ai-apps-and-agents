"""Command-line tool to seed and reset the Customer Success Agent demo data.

Run from the scenario root:

    python -m backend.seed_cli seed            # load raw demo turns
    python -m backend.seed_cli seed --process  # load turns and run memory processing
    python -m backend.seed_cli reset           # delete all demo memory records
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from memory_service import MemoryService  # noqa: E402
from seed_data import DEMO_USERS, SEED_DIALOGUES  # noqa: E402


async def seed(*, process: bool) -> int:
    print("Connecting to Cosmos DB and AI Foundry...", flush=True)
    memory = MemoryService()
    await memory.connect()
    print("Connected.", flush=True)

    threads_by_user = {
        user.id: sorted({thread_id for thread_id, _, _ in SEED_DIALOGUES.get(user.id, [])}) for user in DEMO_USERS
    }
    total_threads = sum(len(threads) for threads in threads_by_user.values())

    total_seeded = 0
    total_skipped = 0
    total_processed = 0
    step = 0

    try:
        for user in DEMO_USERS:
            print(f"\n{user.name} ({user.id}) - {len(threads_by_user[user.id])} thread(s)", flush=True)
            for thread_id in threads_by_user[user.id]:
                step += 1
                prefix = f"  [{step}/{total_threads}] {thread_id}"
                turns = [
                    (role, content)
                    for seed_thread_id, role, content in SEED_DIALOGUES[user.id]
                    if seed_thread_id == thread_id
                ]

                print(f"{prefix}: seeding {len(turns)} turn(s)...", flush=True)
                result = await memory.seed_thread_if_empty(user_id=user.id, thread_id=thread_id, turns=turns)
                if result == "seeded":
                    total_seeded += 1
                    print(f"{prefix}: seeded {len(turns)} turn(s).", flush=True)
                else:
                    total_skipped += 1
                    print(f"{prefix}: already seeded, skipped.", flush=True)

                if process:
                    print(f"{prefix}: processing (extract memories + thread summary + user summary)...", flush=True)
                    await memory.process_thread(user_id=user.id, thread_id=thread_id)
                    total_processed += 1
                    print(f"{prefix}: processed.", flush=True)
    finally:
        print("\nClosing connections...", flush=True)
        await memory.close()

    print(
        f"\nDone. {total_seeded} thread(s) seeded, {total_skipped} skipped"
        + (f", {total_processed} processed." if process else ".")
    )
    return 0


async def reset() -> int:
    print("Connecting to Cosmos DB and AI Foundry...", flush=True)
    memory = MemoryService()
    await memory.connect()
    print("Connected.", flush=True)
    demo_user_ids = [user.id for user in DEMO_USERS]
    try:
        print(f"Deleting demo records across {len(demo_user_ids)} account(s)...", flush=True)
        deleted = await memory.reset_demo_records(user_ids=demo_user_ids)
    finally:
        print("Closing connections...", flush=True)
        await memory.close()
    print(f"Deleted {deleted} demo memory record(s) across {len(demo_user_ids)} account(s).")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Seed or reset the Customer Success Agent demo data.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    seed_parser = subparsers.add_parser("seed", help="Load raw demo turns for every demo account.")
    seed_parser.add_argument(
        "--process",
        action="store_true",
        help="Also run memory extraction and summarization after seeding each thread.",
    )

    subparsers.add_parser("reset", help="Delete all demo memory records.")

    args = parser.parse_args(argv)

    if args.command == "seed":
        return asyncio.run(seed(process=args.process))
    if args.command == "reset":
        return asyncio.run(reset())
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
