// Read-only: for each write the app recorded as refused (a "replay" refusal), does the THROWAWAY server (bd40c50a)
// already hold the refused values? Prints per-entity matches; never writes.
import { init } from '/Users/laptop/Sync/worktrees/foldkit-words/node_modules/.pnpm/@instantdb+admin@1.0.53/node_modules/@instantdb/admin/dist/esm/index.js'
import { readFileSync } from 'node:fs'
if (!process.env.INSTANT_APP_ID?.startsWith('bd40c50a')) throw new Error('throwaway app only')
const db = init({ appId: process.env.INSTANT_APP_ID, adminToken: process.env.INSTANT_APP_ADMIN_TOKEN })
const writes = JSON.parse(readFileSync('/tmp/fd-sim/r023/failed-writes.json', 'utf8'))
const decode = (v) => {
  if (v == null) return undefined
  if ('string' in v) return v.string._0
  if ('number' in v) return v.number._0
  if ('bool' in v) return v.bool._0
  if ('boolean' in v) return v.boolean._0
  if ('null' in v) return null
  if ('json' in v) {
    const un = (j) => {
      if (j == null) return null
      const [k] = Object.keys(j); const x = j[k]?._0 ?? j[k]
      if (k === 'object') return Object.fromEntries(Object.entries(x).map(([a, b]) => [a, un(b)]))
      if (k === 'array') return x.map(un)
      if (k === 'null') return null
      return x
    }
    return un(v.json._0)
  }
  return { unsupported: Object.keys(v)[0] }
}
const summary = { entityMissing: 0, allMatch: 0, someDiffer: 0 }
for (const w of writes) {
  const result = await db.query({ [w.namespace]: { $: { where: { id: w.entityID } } } })
  const row = result[w.namespace][0]
  if (!row) { summary.entityMissing++; console.log(`MISSING ${w.namespace} ${w.entityID.slice(0, 8)} (${w.mutationID.slice(0, 8)})`); continue }
  const differ = []
  for (const [attr, value] of Object.entries(w.attributes)) {
    const local = decode(value)
    if (local && typeof local === 'object' && 'unsupported' in local) continue
    if (['recording', 'transcription'].includes(attr)) continue
    const server = row[attr]
    const same = JSON.stringify(server) === JSON.stringify(local) ||
      (typeof server === 'number' && typeof local === 'number' && Math.abs(server - local) < 1e-6)
    if (!same) differ.push(`${attr}: local=${JSON.stringify(local)?.slice(0, 40)} server=${JSON.stringify(server)?.slice(0, 40)}`)
  }
  if (differ.length === 0) summary.allMatch++; else summary.someDiffer++
  console.log(`${differ.length ? 'DIFFERS' : 'MATCHES'} ${w.namespace} ${w.entityID.slice(0, 8)} (${w.mutationID.slice(0, 8)})${differ.length ? ' | ' + differ.slice(0, 3).join('; ') : ''}`)
}
console.log(JSON.stringify(summary))
