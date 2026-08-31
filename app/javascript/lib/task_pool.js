export async function runPool(tasks, concurrency) {
  const queue = tasks.slice()
  const workers = Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
    while (queue.length > 0) {
      // A task reports its own failure, so a throw here must not take the worker — and
      // with it the rest of the queue — down with it.
      try { await queue.shift()() } catch { /* already surfaced by the task */ }
    }
  })
  await Promise.all(workers)
}
