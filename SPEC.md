# SPEC: utxo-privacy — local, read-only UTXO privacy audit and coin-control planner

Status: draft 2026-11-02 (interview complete, not started)

## 1. Problem

Self-custodial Bitcoin users who run their own Bitcoin Core node, either directly or as the
backend for a hardware wallet via a watch-only descriptor wallet, have no way to see the
privacy damage in their coins before they spend them.

- **Core gives control but no judgement.** It has manual coin control, `avoid_reuse` and
  `avoidpartialspends`, but it never tells you that two coins come from different sources,
  that your change is trivially identifiable, or that a 546-sat coin is a dust attack.
  Users learn about the leak after it is on-chain, and on-chain leaks are permanent.
- **The existing analysis tools leak the thing they analyse.** Explorer "privacy score"
  pages and online tx analysers require submitting txids, addresses or an xpub to a third
  party, which links those coins to your IP and session.
- **The common leaks are mechanical and detectable:** address reuse; change identifiable by
  script type, round payment amounts or unnecessary inputs; peel chains; merging KYC with
  non-KYC coins; undoing a coinjoin by merging mixed outputs with unmixed coins or toxic
  change; spending dust-attack outputs.

The tool must **never** send wallet data anywhere except the user's own node. It must never
change wallet state, sign, broadcast, or write wallet data to disk.

## 2. Scope

### In

- CLI `utxo-privacy` with subcommands `scan`, `utxos`, `plan`, `explain`.
- Backend: Bitcoin Core JSON-RPC against one loaded **descriptor** wallet. Watch-only
  wallets (`disable_private_keys=true`) are fully supported.
- Supported Core versions: the releases inside Core's maintenance window (last 3 majors) at
  implementation time. Checked at startup; anything else is refused clearly.
- Pruned nodes and nodes without `txindex` are supported. The tool needs only wallet data.
- Strictly read-only. An allowlisted RPC client refuses every method outside the list.
- On-chain clustering of the wallet's own coins, from co-spends, change, and shared
  addresses.
- Provenance from Core address labels plus an optional BIP-329 file (`--labels`), read
  locally. A tag convention in label text: `#kyc`, `#nokyc`, `#coinjoin`, `#notcoinjoin`,
  `#donotspend`.
- Heuristic families: address reuse; change identification (script type, round amount,
  UIH1/UIH2); forward linking (peel chains, change reuse); wallet fingerprint; consolidation
  (cross-cluster merges, label mixes, uneconomical UTXOs); generic equal-output coinjoin
  detection; dust attacks.
- Conflicted, replaced and abandoned txs count as linking evidence, marked `mempool-only`
  and reported one severity step lower.
- Planner modes:
  - **pay**: one or more recipients via repeated `--to ADDR:AMOUNT`, batching included.
  - **sweep**: send a whole cluster with no change.
  - **consolidate**: merge coins within a single cluster only.
- Planner output: the top 3 candidates ranked lexicographically, each with its cost spelled
  out and a ready-to-paste `bitcoin-cli` command that produces an **unsigned** PSBT.
- Output formats: human (default) and `--format json` with a versioned schema. `--redact`
  produces shareable reports.
- Exit codes suitable for scripting (§3.9).
- Python ≥ 3.11 with **stdlib only** at runtime. Build backend: `flit_core`. Dev dependency:
  `pytest`, pinned with hashes. E2E tests need Docker.

### Out (explicitly)

- Electrum/Esplora/xpub backends and any third-party server. Querying one would leak the
  wallet graph.
- Any wallet write, by the tool itself: signing, broadcasting, `walletcreatefundedpsbt`,
  `lockunspent`, `setlabel`, `getnewaddress`. The tool *prints* commands; the user runs
  them.
- Legacy (BDB) wallets, and Core versions outside the maintenance window.
- Cross-wallet analysis, i.e. links between two of the user's wallets.
- Fiat-round amount detection, price feeds, and any network access besides the RPC socket.
- Network-layer privacy: broadcast origin, Tor setup, peer behaviour. Also timing analysis.
- Payee-side behaviour that the wallet can't see, such as payee address reuse or the payee's
  spending fingerprint.
- Protocol-specific coinjoin fingerprints (Whirlpool/WabiSabi/JoinMarket), and any coinjoin
  coordination.
- Payjoin creation. Payjoins already in history are analysed, with coverage gaps noted.
- Signature-level fingerprints (low-R grinding) and Lightning-specific heuristics.
- Silent payments.
- A GUI, a TUI, or interactive coin picking.
- On-disk caches, persisted reports, and finding suppression lists.
- Numeric scores and wallet grades.
- Cookie auto-discovery on Windows. Windows users pass `--rpccookiefile`.
- CI workflow wiring. Editing `.github/workflows/**` needs a separate explicit request.
- Lint and type-check tooling (ruff, mypy). These would be new dev dependencies and will be
  proposed separately.

## 3. Design

### 3.1 Pipeline and module boundaries

```
cli ─► rpc.client (allowlist) ─► ingest ─► WalletSnapshot (immutable)
                                              │
                         labels (Core + BIP-329) ─► TagMap
                                              │
                              graph ─► ClusterGraph (chronological union-find)
                                              │
                    heuristics ─► Analysis(findings, utxo_tags, coverage)
                                              │
                        planner ─► [Candidate]   (plan only)
                                              │
                         report (human | json, optional redact) ─► stdout
```

Invariants. These belong in CLAUDE.md's Architecture section once implementation starts.

1. **Only `rpc/` does I/O to the node, and only `ingest` uses `rpc/`.** `labels` reads the
   one BIP-329 file. Everything from `graph` through `planner` is a pure function of its
   inputs: no I/O, no clock, no randomness. Output is deterministic and byte-identical
   across runs on the same snapshot.
2. **No RPC method outside `ALLOWED_METHODS` is ever sent**, and nothing leaves the process
   except to the RPC endpoint. Nothing is written to disk.
3. `report` is the only module that writes to stdout. Diagnostics go to stderr.

### 3.2 Files

| Path | Responsibility |
| --- | --- |
| `pyproject.toml` | flit_core build, `utxo-privacy = utxo_privacy.cli:main`, no runtime deps |
| `requirements-dev.txt` | pytest and its transitive deps, pinned with `--require-hashes` |
| `src/utxo_privacy/cli.py` | argparse, subcommands, exception→exit-code mapping |
| `src/utxo_privacy/errors.py` | exception types, each bound to an exit code |
| `src/utxo_privacy/amounts.py` | Decimal BTC ↔ int sats; CLI amount parsing (`100000sat`, `0.001btc`) |
| `src/utxo_privacy/sanitize.py` | terminal-safe strings (strip C0/C1 controls, ANSI), shell quoting |
| `src/utxo_privacy/rpc/endpoint.py` | host resolution, loopback check, per-chain default port |
| `src/utxo_privacy/rpc/auth.py` | cookie discovery, `--rpcuser` + env/getpass password |
| `src/utxo_privacy/rpc/transport.py` | urllib JSON-RPC: no proxies, no redirects, body cap, batching |
| `src/utxo_privacy/rpc/client.py` | `RpcClient`, `ALLOWED_METHODS`, per-method param guards |
| `src/utxo_privacy/ingest.py` | preconditions + snapshot building |
| `src/utxo_privacy/model.py` | frozen dataclasses (below) |
| `src/utxo_privacy/labels.py` | Core labels, BIP-329 parser, tag extraction and propagation |
| `src/utxo_privacy/graph.py` | clustering and chronological merge events |
| `src/utxo_privacy/heuristics/{reuse,change,forward,fingerprint,consolidation,coinjoin,dust}.py` | one family per file; `heuristics/__init__.py` holds the registry of id → fn, severity, explain text |
| `src/utxo_privacy/planner/{pool,sizes,search,cost,modes,render}.py` | eligibility and address groups; vsize tables; bounded search; cost tuple; pay/sweep/consolidate; `bitcoin-cli` rendering |
| `src/utxo_privacy/report/{human,jsonout,redact}.py` | renderers and redaction |
| `tests/unit/`, `tests/integration/`, `tests/e2e/` | see §5 |
| `tests/fixtures/rpc/`, `tests/fixtures/bip329/` | recorded **regtest-only** RPC responses; label files |
| `scripts/record_fixtures.py` | dev tool; refuses to run unless `getblockchaininfo.chain == "regtest"` |
| `docker/regtest/Dockerfile` | `debian:stable-slim@sha256:<pinned>` + Core tarball verified against a pinned SHA256 (`ARG CORE_VERSION`, `ARG CORE_SHA256`) |

### 3.3 Interfaces

These are signatures only. Bodies are left to implementation.

- `RpcClient.call(method, *params) -> Any` and
  `RpcClient.batch(calls: list[tuple[str, tuple]]) -> list[Any | RpcError]`. Both raise
  `ForbiddenRpcMethod` **before any bytes are sent** if a method isn't allowlisted.
- `ingest.load_snapshot(client, wallet, *, allow_incomplete) -> WalletSnapshot`
- `labels.load_bip329(path) -> LabelSet` and
  `labels.resolve(snapshot, core_labels, label_set) -> TagMap`
- `graph.build(snapshot, tags) -> ClusterGraph`, which provides `cluster_of(outpoint)`,
  `clusters`, and `events`. `events` is a chronological list of merges, each with its txid
  and evidence kind.
- `heuristics.run_all(snapshot, graph, tags, cfg) -> Analysis`
- `planner.plan(request, snapshot, graph, analysis, cfg) -> list[Candidate]`
- `report.render(result, fmt, *, redact, salt) -> str`. The salt is injected so tests are
  deterministic.

Core model types are frozen dataclasses with `slots`:

- `Outpoint(txid, vout)`
- `TxOut`: `n`, `value_sat`, `script_type`, `address | None`, `owned`, `is_change | None`
- `TxIn`: `prevout`, `value_sat | None`, `script_type | None`, `owned`, `sequence`
- `Tx`: `txid`, `version`, `locktime`, `vsize`, `inputs`, `outputs`, `status`, `height | None`,
  `time`, `fee_sat | None`. `status` is one of `confirmed`, `mempool`, `conflicted`,
  `abandoned`.
- `Utxo`: `outpoint`, `value_sat`, `address`, `confirmations`, `locked`
- `WalletSnapshot`: `chain`, `tip_height`, `wallet_name`, `txs`, `utxos`, `address_info`,
  `internal_types`, `core_labels`, `coverage_seed`
- `Finding`: `id`, `heuristic`, `severity`, `evidence_kind` (`chain` or `mempool-only`),
  `title`, `txids`, `outpoints`, `addresses`, `fix`, `detail`
- `Coverage`: `txs_total`, `txs_analysed`, `skipped` (list of heuristic, count, reason),
  `incomplete` (list of reasons), and `unobservable` (fixed list)

All amounts are integer sats. Core's JSON is parsed with `parse_float=Decimal`, and any
amount that isn't a whole number of sats is rejected.

### 3.4 RPC surface (complete allowlist)

| Method | Used for |
| --- | --- |
| `getnetworkinfo` | Core version gate |
| `getblockchaininfo` | `chain` match, `initialblockdownload`, `pruned`, `blocks` |
| `getbestblockhash` | snapshot consistency: compare at start and end |
| `listwallets` | wallet selection |
| `getwalletinfo` | `descriptors` flag, `scanning`, `private_keys_enabled` |
| `listdescriptors` | active **internal** descriptor types, i.e. which change types exist. The client **forces `private=false`**, and descriptors are never output |
| `listsinceblock` | full history: `("", 1, true, false, true)`, with include_change |
| `gettransaction` | `(txid, true, true)` to get the decoded tx, batched |
| `getaddressinfo` | owned addresses only: `ischange`, `labels`, `desc` |
| `listunspent` | current UTXOs, `minconf=0` |
| `listlockunspent` | exclude locked coins in the planner |
| `estimatesmartfee` | fee rate when `--feerate` is omitted |
| `validateaddress` | `--to` validation and network check |

Ownership comes from `listsinceblock` entries (`vout`, `category`), including change. An
input is owned if its prevout is an owned output. `getrawtransaction` is deliberately absent,
so foreign-input values are unknown. Txs with foreign inputs (coinjoins, payjoins) are
excluded from UIH and fee-rate checks and listed in Coverage.

Wallet RPCs go to `/wallet/<urlquote(name, safe="")>`. Core wallet names can contain `/`.

### 3.5 Connection, auth and preconditions

- **Endpoint.** The default is `127.0.0.1` on the chain's default port: 8332, 18332, 48332,
  38332, 18443. The host is resolved **once**. Every resolved address must be loopback,
  unless `--allow-remote` is passed, which prints a cleartext warning recommending
  SSH/WireGuard. The tool connects to the resolved IP and sends the original Host header.
- **Transport.** It is built with `ProxyHandler({})`, so `HTTP(S)_PROXY` are ignored, and
  with no redirect handling (a 3xx is an error). It has a response body cap (256 MiB) and a
  `--timeout` (30 s). It does not retry.
- **Auth precedence.**
  1. `--rpccookiefile`.
  2. `--rpcuser` with the password from `BITCOIN_RPC_PASSWORD`, else a `getpass` prompt.
  3. Cookie auto-discovery at `<datadir>/[testnet3|testnet4|signet|regtest/].cookie`.
     `datadir` is `--datadir`, `~/.bitcoin` on Linux, or
     `~/Library/Application Support/Bitcoin` on macOS.

  There is **no `--rpcpassword` flag**, and `bitcoin.conf` is never parsed.
- **Preconditions, checked in order.** Each failure maps to an exit code:
  1. The Core version is in the supported window. Otherwise exit 3.
  2. `chain` equals `--chain`. Otherwise exit 3.
  3. Wallet selection. With no wallet loaded, exit 3 with a `loadwallet` hint. With several
     loaded and no `--wallet`, exit 2 and list the names, sanitized.
  4. The wallet is a descriptor wallet. Otherwise exit 3.
  5. The node is not in IBD and the wallet is not `scanning`. Otherwise exit 3, unless
     `--allow-incomplete` is passed, which sets `coverage.incomplete`.
  6. The wallet has no active internal descriptor. This is a prominent **warning**, not a
     failure: change outputs aren't tracked, so change heuristics are skipped and recorded in
     coverage.
  7. If the tip moved between start and end, a coverage note is added. There is no automatic
     rerun.

### 3.6 Provenance: clustering and tags

- **Clusters** use a union-find over owned outputs. Txs are processed in chronological order:
  height (unconfirmed and conflicted last), then topological order, then txid.
  - All owned outputs paying the same address are joined.
  - All owned inputs of a tx are joined. This holds even in coinjoins, since the coordinator
    and counterparties may know.
  - Every owned output of a tx with owned inputs joins the input cluster. Change is treated
    as linked **whether or not heuristics identify it**, because a cluster boundary must be
    conservative.
  - **Exception:** an owned equal-value coinjoin output starts a fresh cluster. It is
    *mixed*. The owned non-equal output of that coinjoin (`coinjoin-change`) stays in the
    pre-mix cluster.
  - Conflicted, replaced and abandoned txs contribute merges with
    `evidence_kind = mempool-only`.
  - Cluster ids are assigned in order of first appearance, so they are deterministic.
- **Coinjoin detection.** A tx is a coinjoin if its largest group of equal-value outputs has
  ≥ 3 members, its input count is ≥ that group size, and the wallet owns ≥ 1 output in the
  group. The anonset equals the group size. `#coinjoin` forces detection and `#notcoinjoin`
  suppresses it. Known false positive: exchange batch payouts, which is what `#notcoinjoin`
  is for.
- **Tags.** Sources are Core address labels and BIP-329 records of type `addr`, `tx` and
  `output`. Tx labels apply to the owned outputs of that tx. `input`, `xpub` and `pubkey`
  records are ignored in v1. Tags are matched case-insensitively as whole tokens.
  - Change outputs inherit the union of their input tags.
  - BIP-329 `spendable: false` produces the tag `frozen`.
  - Cluster tags are the union of member tags.
  - A coin tagged both `#kyc` and `#nokyc` keeps both and gets a `labels.conflict` finding.
- **Label-mix rule (critical).** Inputs come from **distinct** clusters, and either one
  cluster has `kyc` and another has `nokyc`, or a mixed cluster is combined with a non-mixed
  one. Two mixed clusters merged together are only `cross-cluster` (high). Coins already in
  one cluster never trigger it, because re-merging reveals nothing new.

### 3.7 Heuristics and findings

Some definitions:

- A **send** is a wallet tx where every input is owned.
- The **ground-truth change** is the owned output whose address has `ischange=true`.
- Change checks run as an **adversary simulation** on each send with ≥ 2 non-OP_RETURN
  outputs and exactly one ground-truth change. Each method guesses an output without using
  ownership data. Only a **correct** guess produces evidence.

| Finding | Trigger | Severity |
| --- | --- | --- |
| `reuse.address` | owned address received in ≥ 2 distinct non-dust txs | high if an unspent coin remains on it, else medium |
| `reuse.change` | ground-truth change paid to an address that had already received | high |
| `reuse.payee-repeat` | the same external address paid in ≥ 2 sends | medium |
| `change.identifiable` | ≥ 1 method correctly picks the change; `detail.methods` lists them | medium; high if ≥ 2 methods agree |
| — method `script-type` | exactly one output's script type is in the inputs' type set and ≥ 1 output's isn't → guess that output | |
| — method `round-amount` | an output is round when `value_sat % 10_000 == 0`. If all outputs but one are round → guess the non-round one | |
| — method `uih1` | ≥ 2 inputs, 2 outputs, one output < min(input), the other > max(input) → guess the smaller | |
| `selection.unnecessary-input` | UIH2: ≥ 2 inputs and `sum(in) − min(in) ≥ max(out) + fee` | low |
| `forward.peel-chain` | sends T1→…→Tk, each spending the previous one's identifiable change | medium at k = 2, high at k ≥ 3 |
| `fingerprint.change-position` | 2-output sends, n ≥ 8, and the change index fails a two-sided exact binomial test (p = ½) at p < 0.01 | high |
| `fingerprint.output-order` | all of ≥ 8 multi-output sends are BIP69-ordered | low |
| `fingerprint.change-continuity` | change later spent by an owned tx with an identical fingerprint tuple. One aggregate finding; the payee side is unobservable | low |
| `fingerprint.summary` | always reported: nVersion, locktime class (zero, height, time), RBF share, integer-feerate share, ordering class | info |
| `consolidation.cross-cluster` | a past tx co-spent inputs from ≥ 2 clusters, as of just before that tx | high |
| `consolidation.label-mix` | the same, plus the label-mix rule. Replaces cross-cluster for that tx | critical |
| `consolidation.uneconomical` | aggregate: UTXOs whose spend cost at `--ref-feerate` (25 sat/vB) is > 10% of their value | low |
| `coinjoin.toxic-change` | an unspent `coinjoin-change` UTXO | medium |
| `dust.attack` | an owned UTXO ≤ `--dust-threshold` (1000 sat) from a tx with no owned inputs | high if the address had received before, else medium |
| `labels.conflict` | a coin tagged both `#kyc` and `#nokyc` | low |

A `mempool-only` finding drops one step: critical→high→medium→low. Info stays info.

A finding id is `<heuristic>:<first 8 hex of sha256(sorted evidence)>`. Under `--redact` the
hash is keyed with the run salt, so nobody can confirm a guessed txid against a shared
report.

UTXO tags: `reused-addr`, `linkable-change`, `dust-attack`, `coinjoin-output` (with
`anonset`), `coinjoin-change`, `kyc`, `nokyc`, `donotspend`, `frozen`, `locked`,
`uneconomical`, `unconfirmed`, `mempool-linked`, and `cluster:N`.

Coverage always lists what it can't see: payee-side spends, fiat-round amounts,
network-layer leaks, timing. It also counts the txs skipped per heuristic, with a reason
(foreign inputs, more than one change output, no internal descriptor).

### 3.8 Planner

**Eligibility.** The candidate pool starts from `listunspent` with `minconf=1`, or 0 with
`--include-unconfirmed`. It excludes:

- `dust-attack`, `donotspend` and `frozen` coins, plus locked coins
- outpoints passed with `--exclude TXID:VOUT`
- coins whose input size can't be estimated

**Units.** The planner selects **address groups**: all eligible coins on one address are
spent together or not at all. Dust-attack coins never join a group.

**Sizes.** Input vsize uses standard worst-case values: P2PKH 148, P2SH-P2WPKH 91,
P2WPKH 68, P2TR key-path 57.5. For `wsh(multi|sortedmulti(k,…))` the size is derived from
`getaddressinfo.desc`. Output sizes and the segwit/legacy overhead come from the same table.

**Cost tuple.** Candidates are ranked lexicographically, lower is better:

1. critical label mixes created
2. new cluster links, counted as distinct clusters minus 1
3. change methods that would correctly identify the planned change (0 if changeless)
4. input count
5. fee + overpay, in sats
6. tie-break on the sorted outpoint list

**Search.** The search is deterministic and bounded:

1. **Per cluster, changeless.** A depth-first branch-and-bound over units sorted by effective
   value (descending), then outpoint. It looks for a total in
   `[target_nochange, target_nochange + max_overpay]`. The cap is 100,000 iterations per
   cluster. `max_overpay` defaults to min(2000 sat, 1% of total payments).
2. **Per cluster, with change.** It covers `target_change + dust(change_type)` with the
   fewest units: largest first, plus single-unit alternatives. It keeps the best 5 per
   cluster by cost.
3. **Multi-cluster.** This runs only if no single cluster can pay. It tries k = 2, 3, …
   clusters, non-conflicting combinations first, with at most 10,000 combinations, and stops
   at the first k that yields candidates.
4. All candidates are merged, deduplicated, sorted by cost, and the top `--top` (3) are
   output.

**Change type.** The change type is set to match a payment output's type when the wallet has
an active internal descriptor of that type. Otherwise the planner warns with
`plan.change-type-unmatched`.

**Fingerprint.** `replaceable` and `locktime` follow the wallet's historical majority. A
height-based locktime uses the current tip.

**Fee rate.** It comes from `--feerate` (sat/vB, up to 3 decimals). Otherwise
`estimatesmartfee` is used, with target 6 for pay/sweep and 144 ECONOMICAL for consolidate.
If no estimate is available, exit 2 and ask for `--feerate`.

**Warnings** attached to each candidate:

| Warning | Severity |
| --- | --- |
| `plan.label-mix` | critical |
| `plan.new-link` | high |
| `plan.change-identifiable` | medium; high if ≥ 2 methods |
| `plan.round-payment` | info, unavoidable |
| `plan.payee-repeat` | medium |
| `plan.self-send` | low |
| `plan.batch-links-payees` | medium |
| `plan.change-type-unmatched` | low |
| `plan.fingerprint-mismatch` | low |

**Modes:**

- **pay** — `plan --to ADDR:AMOUNT [--to ADDR:AMOUNT …]`. Amounts need a unit suffix
  (`sat` or `btc`). Bare numbers, values ≤ 0, values > 21M BTC, and more than 8 BTC decimals
  are rejected with exit 2, as are duplicate addresses. Every address must pass
  `validateaddress` on the selected chain.
- **sweep** — `plan --sweep --to ADDR [--cluster ID]`. There is one changeless candidate per
  cluster, with output = Σ − fee. Without `--cluster` it only lists the clusters and renders
  **no command**, because sweeping two clusters to one address would link them.
- **consolidate** — `plan --consolidate [--cluster ID --to ADDR]`. It works only inside a
  cluster, and only for clusters with ≥ 2 units and positive savings. Savings are the future
  spend cost at `--ref-feerate`, minus the consolidation fee now, minus the cost of spending
  the merged output later. A command is rendered only with `--cluster` and `--to`. `--to`
  must be `ismine` and have **never received**, otherwise exit 2. The tool can't call
  `getnewaddress`, so the user provides a fresh address.

**Rendered commands** (in `render.py`). The output is an **unsigned** PSBT, and no broadcast
command is ever printed.

- With change:
  `bitcoin-cli [-chain flag] -rpcwallet=<quoted> walletcreatefundedpsbt '<inputs>' '<outputs>' <locktime> '{"add_inputs":false,"change_type":…,"fee_rate":…,"replaceable":…}'`
- Changeless:
  `PSBT=$(bitcoin-cli … createpsbt '<inputs>' '<outputs>' <locktime> <replaceable>) && bitcoin-cli … walletprocesspsbt "$PSBT" false`.
  The exact amounts mean Core does no fee estimation on this path.
- A review hint is appended: `decodepsbt` / `analyzepsbt`.
- Dust attacks are rendered as
  `bitcoin-cli … lockunspent false '[{"txid":…,"vout":…}]' true`.
- Rules for every command:
  - The wallet name goes through `shlex.quote`.
  - Txids are checked to be 64 hex characters, and addresses are node-validated before they
    are interpolated.
  - BTC amounts are formatted from int sats with exactly 8 decimals.
  - Label text is **never** interpolated.
  - Credentials never appear.
  - `-rpcconnect/-rpcport` are added only when they differ from the defaults.
- Under `--redact`, no command is printed.

### 3.9 CLI surface and exit codes

```
utxo-privacy [global] scan
utxo-privacy [global] utxos
utxo-privacy [global] plan (--to ADDR:AMOUNT ... | --sweep --to ADDR [--cluster N]
                            | --consolidate [--cluster N --to ADDR])
                           [--feerate R] [--max-overpay SAT] [--top N]
                           [--include-unconfirmed] [--exclude TXID:VOUT ...]
utxo-privacy explain [FINDING_OR_METHOD_ID]        # offline, no RPC
```

Global options are accepted before or after the subcommand:
`--chain {main,test,testnet4,signet,regtest}`, `--rpc-host`, `--rpc-port`, `--datadir`,
`--rpccookiefile`, `--rpcuser`, `--wallet`, `--allow-remote`, `--allow-incomplete`,
`--labels PATH`, `--format {human,json}`, `--redact`, `--debug`,
`--fail-on {critical,high,medium,low,info,never}` (default `high`),
`--dust-threshold SAT`, `--ref-feerate R`, `--timeout S`.

| Exit code | Meaning |
| --- | --- |
| 0 | ok. For `plan`: the top candidate has no warning ≥ `--fail-on` |
| 1 | `scan`/`utxos`: a finding ≥ `--fail-on`. `plan`: the top candidate has a warning ≥ `--fail-on` |
| 2 | usage error: bad flags or amounts, unknown id, ambiguous wallet, invalid or unsuitable `--to`, missing fee estimate |
| 3 | precondition: version, chain, legacy wallet, IBD/scanning, no wallet loaded, insufficient eligible funds (the message shows excluded totals by reason) |
| 4 | RPC, transport or auth failure: unreachable, timeout, 401, 3xx, oversized body, malformed JSON |

`scan` human output has four sections: Summary, Findings by severity, Clusters, Coverage.
`utxos` prints a table of outpoint, value, confirmations, type, cluster, tags, and label
(sanitized, truncated to 40 characters). JSON output is one object with `schema_version: 1`,
`tool_version`, `chain`, `wallet`, `tip_height`, `findings`, `utxos`, `clusters`,
`coverage`. For `plan` it also has `candidates[]`, each holding inputs, outputs, change,
`est_vsize`, `fee_sat`, `feerate`, `overpay_sat`, `cost`, `warnings`, and `command`.

### 3.10 Assumptions to verify in the first slice

If any of these fails, amend the spec before building on it.

1. `listsinceblock("", 1, true, false, true)` returns, on every supported version:
   change-only consolidations, conflicted and replaced txs (negative `confirmations`), and
   abandoned txs.
2. `walletcreatefundedpsbt` with `add_inputs:false`, `change_type` and an explicit locktime
   yields exactly the planned inputs plus one change output. The `createpsbt` path yields
   exactly the planned outputs.
3. `lockunspent`'s `persistent` argument exists on every supported version.
4. An `rpcauth` user restricted with `rpcwhitelist` to `ALLOWED_METHODS` can run every
   command. The docs will print this whitelist line.

### 3.11 Alternatives rejected

| Alternative | Why rejected |
| --- | --- |
| Electrum/xpub backend | it leaks the wallet graph to a server, and needs derivation and gap-limit code |
| Offline export mode | wallet export formats are inconsistent and history may be incomplete |
| Go or Rust | Python stdlib keeps runtime dependencies at zero and makes the code easy to audit. Rust crates would duplicate Core's decoding |
| PSBT creation via RPC, or `lockunspent` | both are wallet writes. `walletcreatefundedpsbt` can reserve change addresses |
| Encrypted on-disk cache | it leaves a wallet-graph artifact on disk and adds key handling |
| Numeric score or grade | false precision, and a single grade hides which coins are the problem |
| Weighted cost with a privacy knob | arbitrary weights and unexplainable rankings |
| Protocol-specific coinjoin rules | they need maintenance every time a protocol changes |
| Treating unidentified change as unlinked | not conservative: the observer still knows one output is change |
| Ignoring replaced txs | mempool observers saw their input sets |
| Random tie-breaking or randomized output order | breaks determinism. Changeless txs have no change position to hide |
| Parsing `bitcoin.conf` | it is a credential file and the tool doesn't need it |
| `getrawtransaction`/txindex for foreign prevouts | it would break pruned-node support for a rare benefit (payjoin UIH) |

## 4. Security & privacy

**Data touched, in memory only.** Wallet tx history, owned addresses, labels, balances, and
active descriptors. Only the script types of descriptors are used, and they are never
output. RPC credentials. Optionally, the user's BIP-329 file.

**Trust boundaries:**

| Boundary | Trust | Controls |
| --- | --- | --- |
| tool ↔ bitcoind RPC | The node is trusted for **correctness** (a lying node gives bad advice, which is out of scope). It is untrusted for **safety** | method allowlist; `listdescriptors` forced `private=false`; loopback by default with resolve-once; no proxies or redirects; 256 MiB body cap; strict type, hex and amount validation |
| tool ← BIP-329 file | untrusted input | 50 MiB file cap and 64 KiB line cap (over either → exit 2); malformed lines skipped and counted in coverage; unknown fields ignored; never executed or interpolated |
| tool → terminal | output sink | every node-sourced or file-sourced string is passed through `sanitize` (strips C0/C1 controls and ANSI) in human output. JSON escapes controls natively |
| tool → user's shell (rendered commands) | the user will paste them | only validated txids and addresses, int-formatted amounts, `shlex.quote`d wallet name; no labels; no credentials |

**New attack surface.** A crafted wallet name or label can attempt terminal-escape or shell
injection, which the sanitize and quoting rules above block. A wallet name can attempt URL
path tricks, which percent-encoding blocks. `HTTP_PROXY` could exfiltrate credentials and
wallet data, but proxies are disabled. A `localhost` entry pointing at a remote IP is caught
by the resolved-IP loopback check. A redirect to a third host is blocked because 3xx is
refused. Memory exhaustion is limited by the caps.

**Credentials.**

- Cookie or env/getpass only. There is no `--rpcpassword` flag, so passwords stay out of
  `ps` and shell history.
- Credentials never appear in logs, exception messages, `repr(RpcClient)`, rendered
  commands, or JSON.
- The password env var is visible to the same UID via `/proc`. This is documented as
  acceptable.
- The docs recommend a dedicated `rpcauth` user with `rpcwhitelist` restricted to the
  allowlist, as a second layer behind the client's own check.

**Network and disk.** The only socket is the RPC endpoint. There is no telemetry, update
check or price feed. Nothing is ever written to disk, including caches and logs. Tests
enforce both with audit hooks (§5).

**What is logged and what is redacted:**

| Data | stdout (default) | stdout `--redact` | stderr `--debug` | disk |
| --- | --- | --- | --- | --- |
| RPC credentials | never | never | never | never |
| txids, outpoints, addresses | yes | `tx:`/`addr:` + 6 hex of HMAC-SHA256(run salt, value) | no | never |
| amounts | sats | buckets (<10k, 10k–100k, 100k–1M, 1M–10M, 10M–1 BTC, >1 BTC) | no | never |
| label text | sanitized, truncated | dropped (tags kept) | no | never |
| wallet name | yes | `wallet` | no | never |
| block heights / tip | yes | dropped | no | never |
| descriptors / xpubs | never | never | never | never |
| rendered commands | yes | omitted | no | never |
| RPC method names, batch sizes, timings, counts | no | no | yes | never |

The redaction salt is 16 bytes from `secrets` and is fresh on every run. Tokens are stable
within one report, so relationships stay visible, but they can't be linked across reports.
Error messages may contain Core's own error text and are not redacted. This is documented.

**User-facing caveats** for the README and `explain`. Stdout holds a full map of the wallet.
Pasted commands land in shell history; a leading space with `HISTCONTROL=ignorespace` or
`HIST_IGNORE_SPACE` keeps them out. `--allow-remote` sends everything in cleartext.

## 5. Test plan

The test rules apply: write the failing test first, one behaviour per test, mock only at
process boundaries, and keep everything deterministic. There are three layers:

- **unit**: pure functions over hand-built `WalletSnapshot` objects.
- **integration**: the CLI in-process, with a fake transport replaying recorded regtest
  fixtures. Transport tests use an in-process `http.server` on `127.0.0.1` with an
  ephemeral port.
- **e2e**: `pytest -m e2e`, Docker regtest.

The default run is `python -m pytest -m "not e2e"`.

### Clustering and provenance (unit)

- Two coins on the same address end up in one cluster.
- Co-spent inputs end up in one cluster, and the change joins it.
- An incoming payment from foreign inputs starts a new cluster.
- A coinjoin equal output starts a fresh *mixed* cluster, while the coinjoin change stays in
  the pre-mix cluster.
- 3 equal outputs with 1 input (a batch payout) is not a coinjoin. 5 equal outputs with 5
  inputs, owning one, gives anonset 5.
- `#notcoinjoin` suppresses detection and `#coinjoin` forces it.
- A replaced tx's inputs are still joined, with `mempool-only` evidence. An abandoned tx's
  inputs are also joined.
- Chronology: a cross-cluster finding fires only when the clusters were distinct before that
  tx. Merging coins that were already linked fires nothing.
- Tags propagate: change inherits the tags of its inputs. Cluster tags are the union of
  member tags.
- Mixing `#kyc` and `#nokyc` within one existing cluster is not a label-mix. Mixing them
  across clusters is critical.

### Heuristics (unit)

Each method gets a positive case, a negative case, and a wrong-guess case that must produce
no finding.

- **Reuse**
  - Received twice with a coin remaining → high.
  - Received twice and fully spent → medium.
  - Change paid to a used address → `reuse.change`.
  - Paying the same external address twice → `reuse.payee-repeat`.
  - Receiving once → no finding.
  - A dust receipt doesn't by itself make an address count as reused.
- **script-type**
  - P2WPKH inputs, P2TR payment and P2WPKH change → identified.
  - All outputs the same type → no guess.
- **round-amount**
  - A 100,000 sat payment with 37,211 change → identified.
  - Both outputs round → no guess.
  - Round change with a non-round payment → wrong guess, no finding.
- **uih1**
  - Inputs 2 and 3 BTC, outputs 4 and 0.9999 → change (0.9999) identified.
- **UIH2**
  - Inputs 5 and 1 BTC, outputs 2 and ~3.9999 → `selection.unnecessary-input`.
- **Agreement and skips**
  - Two methods agreeing → high.
  - A single-output send is skipped.
  - A send with 2 change outputs is skipped, with a coverage entry.
  - Txs with foreign inputs are excluded from UIH, with a coverage entry.
- **Peel chains**
  - 3 sends in a row with identifiable change → `forward.peel-chain` high, length 3.
  - An unidentifiable link in the middle splits the chain.
- **Fingerprint**
  - Change last in 8 of 8 two-output sends → high.
  - 7 of 8 → none (p ≈ 0.07).
  - Fewer than 8 sends → none.
  - All BIP69-ordered across 8 sends → low.
  - Change spent by an identical-fingerprint tx → one aggregate low finding.
  - The summary counts are correct for a mixed nVersion and locktime set.
- **Consolidation**
  - A historical cross-cluster co-spend → high.
  - kyc + nokyc → critical, reported once (not also as cross-cluster).
  - A mixed output co-spent with an unmixed one → critical.
  - Two mixed outputs → high.
  - Uneconomical UTXOs at a 25 sat/vB reference → one aggregate low finding plus a tag on
    each coin.
  - A mempool-only label-mix → high, not critical.
- **Dust**
  - An unsolicited 546 sat coin to an address that received before → high, and the
    `lockunspent` command is rendered.
  - 546 sat change from our own tx → not dust.
  - Exactly `--dust-threshold` counts; threshold + 1 doesn't.
- **Labels**
  - BIP-329 `addr`, `tx` and `output` records apply. `spendable:false` → `frozen`.
  - A malformed line is skipped and counted.
  - A file > 50 MiB → exit 2.
  - Tags match case-insensitively; `#KYC` matches.
  - A coin with both kyc and nokyc → `labels.conflict` plus both tags.
  - A label containing `\x1b[2J` and `\r` is sanitized in human output and valid in JSON.

### Planner (unit)

- An exact-match changeless spend inside one cluster ranks above a cheaper cross-cluster
  spend.
- Overpay of exactly `max_overpay` is changeless. One sat more is not.
- Two coins on one address are always selected together, never one alone.
- A dust-attack coin is never selected, even when it would complete an exact match.
  `frozen`, `donotspend` and locked coins are never selected either.
- The change type matches a P2TR payee when the wallet has an active internal `tr()`
  descriptor. A P2PKH payee with no `pkh()` descriptor gives `plan.change-type-unmatched`.
- A candidate whose change is uih1-identifiable ranks below an equally sized one whose change
  isn't.
- A critical label-mix candidate ranks below every non-critical one, regardless of fee.
- Batch of 3 payees → `plan.batch-links-payees`. Change methods are evaluated against all
  payments.
- `--to` is one of our own addresses → `plan.self-send`. A previously paid address →
  `plan.payee-repeat`.
- Sweep produces one changeless candidate per cluster and no command without `--cluster`.
- Consolidate:
  - It never produces a cross-cluster candidate.
  - It rejects an external `--to` and a used own `--to` with exit 2.
  - It never renders two commands that pay the same address.
- Insufficient eligible funds → exit 3, with excluded totals by reason.
- Determinism:
  - The same snapshot gives byte-identical JSON across two runs.
  - Shuffling the UTXO and tx order of the input gives identical output.
- 200 equal-value UTXOs complete within the iteration cap and still return candidates.
- Amount parsing:
  - Accepted: `100000sat`, `0.001btc`.
  - Rejected with exit 2: `0.001`, `-5sat`, `21000001btc`, `0.000000001btc`, duplicate
    `--to`.
- Rendering:
  - A wallet name `x'; rm -rf ~ #` is quoted so that `shlex.split` gives the literal name back.
  - The JSON arguments parse.
  - The changeless path uses `createpsbt` with the fingerprint's locktime and replaceable
    flag.
  - The output has exactly 8 decimals, and 1 sat renders as `0.00000001`.
  - The output contains no credential.

### RPC, transport, auth and preconditions (integration)

- A forbidden method (e.g. `sendtoaddress`) raises before any request: the wire spy records
  0 requests.
- `listdescriptors` can't be sent with `private=true`.
- Every method used by a full `scan`, `utxos` and every `plan` mode over the fixture wallet
  is in `ALLOWED_METHODS`.
- A non-loopback host without `--allow-remote` → exit 2 with no connection attempted. With
  the flag, a warning goes to stderr.
- A host name that resolves to a non-loopback IP is refused.
- A 3xx response is not followed → exit 4.
- With `HTTP_PROXY` set to a dead port, the request still reaches the local server directly.
- 401 → exit 4, and the message contains neither the cookie value nor the password.
- Cookie discovery works for each chain subdirectory. With no cookie and no `--rpcuser` →
  exit 4 with guidance.
- `--rpcpassword` → argparse error, exit 2.
- `BITCOIN_RPC_PASSWORD` is used, and `getpass` is used when it's unset (getpass patched at
  the boundary).
- Amounts: `0.1` + `0.2` parse to exact sats, `1e-8` parses to 1 sat, and `0.000000015` is
  rejected.
- A body over the cap → exit 4. A partial batch failure in one `gettransaction` → a coverage
  entry, not a crash.
- A wallet name containing `/` and `%` is percent-encoded in the URL path.
- `repr(client)` contains no credential.
- Preconditions:
  - IBD → exit 3; with `--allow-incomplete` → exit 0 or 1 and `coverage.incomplete` set.
  - `scanning` → exit 3.
  - A legacy wallet → exit 3.
  - An unsupported version → exit 3.
  - Chain mismatch → exit 3.
  - Two wallets and no `--wallet` → exit 2.
  - No internal descriptor → a warning, and change heuristics are listed as skipped.
  - A tip change mid-scan → a coverage note.

### Output and privacy (integration)

- `--redact`: every txid, address, label, wallet name and height in the fixture is collected,
  and the test asserts none of them appear anywhere in the output.
- Under `--redact`, tokens are consistent within a run, differ between two salts, and no
  commands are printed.
- `--debug`: stderr contains method names but no params, addresses, labels or cookie text.
- An audit hook (`sys.addaudithook`) during `scan` and `plan` asserts no file is opened for
  writing.
- An audit hook asserts `socket.connect` only ever targets the RPC endpoint.
- JSON has `schema_version: 1` and passes a key-set schema check.
- Exit codes are correct for each `--fail-on` level, for both `scan` and `plan`.
- `explain` works for every registered id with no RPC, and an unknown id → exit 2.

### E2E (`pytest -m e2e`, Docker)

**Harness.** `docker/regtest` is built for the **oldest and newest supported** Core versions.
The suite is parametrized over both. The container:

- runs as the host UID, so the bind-mounted cookie is readable
- publishes RPC on `127.0.0.1:<ephemeral>`

The scenario harness (`tests/e2e/scenario.py`) drives the node through `docker exec
bitcoin-cli`, which has write access. It is test-only, so the product client never gains
write methods. The CLI under test runs as a subprocess with `--chain regtest --rpc-port …
--rpccookiefile …`.

**Scenario.** Txids are random per run, so assertions use structure mapped from the scenario
steps:

1. Receive twice to one address → `reuse.address`.
2. Send a round 0.01 BTC to a P2TR address from a P2WPKH wallet →
   `change.identifiable` (`script-type` + `round-amount`, high).
3. Three chained sends → `forward.peel-chain` length 3.
4. Co-spend two independent receives → `consolidation.cross-cluster`.
5. Label one receive `#kyc` and another `#nokyc`, then co-spend them →
   `consolidation.label-mix` critical.
6. A fake coinjoin among 5 wallets, built with PSBT combine, with 5 equal outputs. The victim
   owns one equal output and one change output → `coinjoin-output` (anonset 5),
   `coinjoin.toxic-change`.
7. An attacker wallet sends 546 sat to the victim's reused address → `dust.attack` high.
8. An RBF send, then a replacement that adds an input → a `mempool-only` link on the
   replaced tx.
9. A BIP-329 file marking one output `spendable:false` and one address `#kyc`.

**Assertions:**

- `scan --format json --labels …` contains every expected finding with the expected severity
  and scenario-mapped evidence, and no other critical findings. Exit code 1.
- `plan --to <P2TR>:<amount>sat --feerate 2` does three things. Its top candidate:
  1. avoids the kyc/nokyc and mixed/unmixed merges
  2. never includes the dust or frozen coin
  3. comes with a rendered command that the **harness** executes, producing a PSBT.
     `decodepsbt` shows exactly the planned inputs, plus one change output of the planned
     type (or none for changeless).
- The rendered `lockunspent` command executes successfully via the harness.
- Assumptions 3.10(1)–(4) are asserted directly.
- **Watch-only variant.** A blank, keyless wallet imports the victim's public descriptors and
  rescans. The tool's finding set (ids, severities, evidence mapping) equals the victim's.
- **Pruned variant.** The node restarts with `-prune=1 -fastprune` and calls
  `pruneblockchain`. The finding set is unchanged and the exit code is the same.

## 6. Verification

The end-to-end proof is one command, which requires Docker. It builds both pinned Core
images, runs the regtest scenario, and drives the installed CLI:

```bash
python -m pip install --require-hashes -r requirements-dev.txt && python -m pip install -e . \
  && python -m pytest -m e2e tests/e2e -v
```

The run passes when every e2e test is green for both Core versions. In particular, the scan
must report each of the scenario's planted leaks at the expected severity. Separately, the
planner's top candidate must avoid the planted critical merges, and the PSBT built from its
rendered command must match the plan exactly.

To inspect by hand, run with `KEEP_REGTEST=1` so the container stays up. The test prints its
RPC port and cookie path. Then run:

```bash
utxo-privacy --chain regtest --rpc-port "$PORT" --rpccookiefile "$COOKIE" --wallet victim scan
utxo-privacy --chain regtest --rpc-port "$PORT" --rpccookiefile "$COOKIE" --wallet victim \
  plan --to "$P2TR_ADDR":250000sat --feerate 2
```

Confirm the following by eye:

- the findings list matches §5's scenario
- `--redact` output contains no txid or address from the regtest wallet
- `strace -f -e trace=connect,openat` shows a single connect to `127.0.0.1:$PORT` and no
  write-mode opens
