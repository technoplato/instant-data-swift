type EventRow = {
  case: string;
  side: "typescript";
  event: string;
  timestampMs: number;
  ok: boolean;
  details?: Record<string, unknown>;
};

function emit(row: Omit<EventRow, "side" | "timestampMs">) {
  console.log(
    JSON.stringify({
      side: "typescript",
      timestampMs: Date.now(),
      ...row,
    }),
  );
}

emit({
  case: "runner",
  event: "blocked-not-implemented",
  ok: false,
  details: {
    reason:
      "TypeScript runner scaffold exists, but InstantSwiftData Swift runner and orchestration are not implemented yet.",
  },
});

process.exit(2);
