export async function runPool(tasks, concurrency) {
  const queue = tasks.slice()
  const workers = Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
    while (queue.length > 0) {
      try { await queue.shift()() } catch { /* already surfaced by the task */ }
    }
  })
  await Promise.all(workers)
}
