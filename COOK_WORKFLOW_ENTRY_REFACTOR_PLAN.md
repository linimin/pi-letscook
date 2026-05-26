# /cook Workflow Entry Refactor Plan

## 目標

把 `/cook` 入口重構成真正符合使用者心智模型的 workflow entry：

- 使用者明確輸入 `/cook`，就代表「開始 workflow entry」
- primary agent 必須在同一個 `/cook` entry 中整理 startup brief / handoff
- **不能**只因為第一個 slice 還不夠 implementation-ready 就拒絕啟動 workflow
- `completion-regrounder` 才是 canonical slice planning authority
- workflow 啟動後應持續推進，直到 mission 完成、被阻塞、或明確需要使用者輸入

一句話版本：

> `/cook` 應該 canonicalize startup intent，然後把 slice 拆分責任交給 `completion-regrounder`；它不應該先做 first-slice 資格審查。`

---

## 使用者期望（本次重構要滿足的產品語義）

### 核心語義

- `/cook` 是 **命令**，不是 **資格審查**
- 使用者下 `/cook`，就是要求系統：
  1. 從 main chat / inline prompt / explicit handoff 整理 startup intent
  2. 顯示 Start / Cancel
  3. Start 後寫入 canonical `.agent/**` workflow state
  4. 交給 `completion-regrounder` 根據 repo truth 拆 slices
  5. workflow 一路推進到 mission 完成

### 不應再發生的行為

以下情況 **不應**再造成 `/cook failed closed`：

- main chat 討論已經很清楚，但 explicit handoff 的 `acceptance` 用語偏設計/討論語氣
- `first_slice_goal` 尚未完全 bounded
- `implementation_surfaces` 尚未明確列出
- `verification_commands` 尚未明確列出
- primary agent 提供的是 mission-level startup brief，而不是 implementer-grade first slice contract

### 仍然可以 fail closed 的情況

本次重構後，只保留以下 fail-closed 類型：

- 使用者按 **Cancel**
- canonical state 寫入失敗
- startup synthesis 技術流程失敗（例如 subprocess/模型回傳空值且沒有任何結構化 fallback）
- active workflow replacement 需要確認但使用者未確認
- 明確的安全 / session 一致性問題（例如 workflow session 衝突）

---

## 現況分析（依目前 codebase）

## 1. `/cook` startup schema 分裂成四套結構

目前 startup 意圖在 code 裡同時以四種形式存在：

1. `CookHandoffCapsule`
   - `extensions/completion/proposal.ts`
2. `ContextProposal`
   - `extensions/completion/proposal.ts`
   - `extensions/completion/driver.ts`（又複製了一套 local type）
3. `AdvisoryStartupBrief`
   - `extensions/completion/prompt-surfaces.ts`
4. persisted `startup-brief.json`
   - `extensions/completion/state-store.ts`

### 造成的問題

- 同一個概念在不同檔案中欄位定義不一致
- first-slice hints 沒有穩定的結構化 schema
- hints 現在多半被塞進 `notes`
- startup policy 容易在不同模組 drift
- `driver.ts` 和 `proposal.ts` 之間型別複製，未來更容易失配

---

## 2. explicit `cook_handoff` 現在被當成 hard gate

### 關鍵程式

- `extensions/completion/proposal.ts`
  - `parseCookHandoffCapsulesFromText()`
  - `cookHandoffStartabilityFailures()`
  - `assessLatestCookHandoffProposal()`
  - `buildNonStartableCookHandoffMessage()`

### 問題

目前 `CookHandoffCapsule` 被要求接近 implementation-ready：

- `mission`
- `scope`
- `acceptance`
- `first_slice_goal`
- `implementation_surfaces`
- `verification_commands`
- `why_this_slice_first`

而 `cookHandoffStartabilityFailures()` 會把以下視為 startup blocker：

- `acceptance is not anchored to concrete repo changes or verification`
- `first_slice_goal is not a bounded implementation slice`
- `implementation_surfaces is empty`
- `verification_commands is empty`

### 實際效果

這等於把 `/cook` 入口當成「first slice implementation-readiness 檢查器」，而不是 workflow entry。

---

## 3. same-entry synthesis 沒有真正整合 explicit handoff 與 main chat

### 關鍵程式

- `extensions/completion/index.ts`
  - `deriveCookStartupProposal()`
  - `deriveCookContextProposal()`
  - `stripCookHandoffBlocks()`

### 問題

目前流程大致是：

1. 先檢查 latest explicit `cook_handoff`
2. 如果它 startable，就直接使用
3. 如果它不 startable，產生 `blockedFailureMessage`
4. same-entry synthesis 時，recent entries 先經過 `stripCookHandoffBlocks()`
5. synthesis 只看到被拿掉 capsule 後的聊天內容 + 一句失敗訊息

### 實際效果

系統不是在做：

> explicit handoff + recent main chat + inline intent + workflow context 的統一 startup synthesis

而是在做：

> 先審核 explicit handoff；如果失敗，就只帶著失敗摘要去重試

這會造成：

- main chat 明明很清楚，但被弱 explicit capsule 反向污染
- synthesis 不能充分利用已有的結構化 handoff 資訊
- explicit handoff 成為 blocker，而不是 input

---

## 4. primary-agent prompt 過度要求 implementation-ready handoff

### 關鍵程式

- `extensions/completion/role-runner.ts`
  - `PRIMARY_AGENT_HANDOFF_SYSTEM_PROMPT`

### 問題

目前 prompt 明講：

- `If the task is not concrete enough for implementation workflow, do not invent the slice.`
- `A valid implementation-ready handoff must include ... first_slice_goal, implementation_surfaces, verification_commands ...`

### 實際效果

same-entry synthesis 即使存在，也還是被要求輸出 implementer-grade first slice contract；
因此 `/cook` 入口依然會被 first-slice readiness 綁死。

---

## 5. `driver.ts` 還把 blocked proposal 視為不能啟動 workflow

### 關鍵程式

- `extensions/completion/driver.ts`
  - `runCookEntry()`
  - `assessActiveWorkflowProposalRouting()`

### 問題

目前 `CookContextProposalResult` 有：

- `proposal?`
- `blockedFailureMessage?`

而 `runCookEntry()` 的 startup / next-round / refocus path 都會在看到 `blockedFailureMessage` 時直接 return。

### 實際效果

只要 startup synthesis 結果不滿足「implementation-startable」，就不會進到 Start / Cancel。

---

## 6. startup brief 已 canonicalize，但 schema 還沒真正 mission-first

### 關鍵程式

- `extensions/completion/state-store.ts`
  - `defaultState()`
  - `defaultStartupBrief()`
- `skills/completion-protocol/SKILL.md`
- `agents/completion-regrounder.md`

### 好的地方

這部分其實已經有正確方向：

- Start 後 workflow 直接進 `current_phase = reground`
- `plan.json` 初始是空的
- `active-slice.json` 初始是 idle
- `startup-brief.json` 被定義成 canonical intake，而不是 canonical slice plan
- `completion-regrounder` 本來就是 slice authority

### 問題

- startup brief 的 hint 欄位尚未正式結構化
- schema 與 prompt 還沒有完全對齊「mission-level startup / regrounder-level slicing」
- `state.json` 裡還保存 `advisory_startup_brief`，可能與 `startup-brief.json` 重複、漂移

---

## 7. driver / routing 還殘留 synthetic prompt 依賴

### 關鍵程式

- `extensions/completion/driver.ts`
  - `queueCompletionDriverPrompt()`
  - `autoContinueWorkflowIfNeeded()`
- `extensions/completion/index.ts`
  - `isCookCommandTurn()`
  - `isCompletionDriverPromptTurn()`
  - `isLikelyWorkflowContinuationTurn()`
  - `isCompletionWorkflowSessionTurn()`

### 問題

雖然 `.agent/current/state.json` 已經有：

- `workflow_entry_status`
- `workflow_session_id`
- `startup_brief_path`

但 driver dispatch 仍然大量依賴：

- synthetic kickoff prompt
- sticky continuation heuristics
- prompt shape detection

### 實際效果

這不是目前最痛的 UX 問題，但它讓 workflow activation 與 dispatch 仍然不夠 canonical-state-first。

---

## 8. docs / tests / release gate 也固化了舊語義

### 關鍵檔案

- `README.md`
- `CHANGELOG.md`
- `skills/cook-handoff-boundary/SKILL.md`
- `scripts/context-proposal-test.sh`
- `scripts/smoke-test.sh`
- `scripts/release-check.sh`

### 問題

這些文件與測試目前都強化了「implementation-first /cook」：

- `/cook` 期待 concrete first slice
- vague handoff 需要被 tightening 到 implementation-ready 才能開始
- release parity 文字也鎖死這個說法

因此重構若只改 code，不改 docs/tests，最終仍會回歸舊模型。

---

## 目標架構

## 核心產品規格

### 1. `/cook` 一定進入 workflow-entry synthesis

只要使用者明確下 `/cook`：

- 一定啟動 startup synthesis
- 一定嘗試整理 mission-level startup brief
- 只要能得到可顯示給使用者確認的 startup brief，就進 Start / Cancel
- 不能因為 first-slice hints 不夠細而提前 fail closed

### 2. explicit `cook_handoff` 是 input，不是 gate

fresh explicit `cook_handoff` 應視為：

- 高權重輸入
- 可被保留 / 補強 / 合併
- 可在不足時被降級成 advisory

但 **不能**反過來阻止 workflow entry。

### 3. startup brief 是 mission-level；slice 由 regrounder author

責任切分應明確：

- startup brief：
  - mission
  - scope
  - constraints / non-goals
  - acceptance
  - risks
  - notes
  - optional hints
- `completion-regrounder`：
  - canonical `plan.json`
  - canonical `active-slice.json`
  - slice selection
  - clarification request if startup brief 尚不足以安全切片

### 4. active-slice exact contract 保持不變

以下 slice-level hard contract 不應被放寬：

- `implementation_surfaces`
- `verification_commands`
- `basis_commit`
- `locked_notes`
- `must_fix_findings`
- reviewer / auditor / stop-judge rubric contract

本次重構只改 **startup entry policy**，不改 **active slice exact contract**。

---

## 重構後的目標流程

```text
/cook
  -> collect startup inputs
     - inline /cook prompt
     - recent main chat
     - fresh explicit assistant-authored cook_handoff
     - canonical workflow context
  -> primary-agent startup synthesis
  -> produce StartupIntentDraft (mission-level)
  -> Start / Cancel
  -> Start 後寫入 canonical startup-brief.json + state.json
  -> next_mandatory_role = completion-regrounder
  -> regrounder 根據 startup brief + repo truth 拆 slices
  -> workflow 持續跑到 done / blocked / await_user_input
```

---

## 新資料模型（建議）

## 1. 新增 `StartupIntentDraft`

建議新增統一 startup-intent module，例如：

- `extensions/completion/startup-intent.ts`

### 建議型別

```ts
type StartupIntentHints = {
  firstSliceGoal?: string;
  firstSliceNonGoals?: string[];
  implementationSurfaces?: string[];
  verificationCommands?: string[];
  whyThisSliceFirst?: string;
};

type StartupIntentDiagnostics = {
  warnings: string[];
  needsClarification: string[];
  confidence?: "high" | "medium" | "low";
};

type StartupIntentSource = {
  inlinePrompt?: string;
  explicitCookHandoffPresent: boolean;
  explicitCookHandoffUsed: boolean;
  recentDiscussionWindowSize: number;
};

type StartupIntentDraft = {
  mission: string;
  scope: string[];
  constraints: string[];
  acceptance: string[];
  risks: string[];
  notes: string[];
  hints: StartupIntentHints;
  diagnostics: StartupIntentDiagnostics;
  source: StartupIntentSource;
  taskType?: string;
  evaluationProfile?: string;
};
```

### 原則

- `mission/scope/constraints/acceptance/risks/notes` 是 startup 核心
- first-slice 相關欄位全部降級為 `hints`
- warnings / needsClarification 只能影響 UI 說明，不直接阻止 Start

---

## 2. persisted `startup-brief.json` schema 擴充

在 `extensions/completion/state-store.ts` 中，將 `startup-brief.json` 擴充為：

```json
{
  "schema_version": 1,
  "artifact_type": "completion-startup-brief",
  "source": "primary_agent_handoff",
  "confirmed": true,
  "confirmed_at": "<ISO-8601>",
  "mission": "<mission>",
  "goal_text": "<display summary>",
  "scope": ["..."],
  "constraints": ["..."],
  "acceptance": ["..."],
  "risks": ["..."],
  "notes": ["..."],
  "first_slice_goal_hint": "<optional>",
  "first_slice_non_goals_hint": ["..."],
  "implementation_surfaces_hint": ["..."],
  "verification_commands_hint": ["..."],
  "why_this_slice_first_hint": "<optional>",
  "startup_confidence": "medium",
  "needs_clarification": ["..."],
  "task_type": "completion-workflow",
  "evaluation_profile": "completion-rubric-v1"
}
```

### 原則

- 這些 hint 欄位全部是 advisory
- `completion-regrounder` 可用也可忽略
- hint 不構成 workflow entry 的 validity gate

---

## 詳細重構計劃

## Phase 0 — 語義翻轉（P0，先解最痛 UX 問題）

### 目標

把 `/cook` 從「implementation-ready startup gate」改成「workflow-entry synthesis」。

### 要做的事

#### `extensions/completion/proposal.ts`

1. 將 `CookHandoffCapsule` 的 first-slice 欄位改為 optional
   - `first_slice_goal?: string`
   - `first_slice_non_goals?: string[]`
   - `implementation_surfaces?: string[]`
   - `verification_commands?: string[]`
   - `why_this_slice_first?: string`

2. 刪除或降級以下 hard gate：
   - `cookHandoffStartabilityFailures()`
   - `buildNonStartableCookHandoffMessage()`
   - `fresh_but_not_startable` status

3. 將 explicit handoff validation 分成兩層：
   - **parse / normalize**：只做 JSON 與來源合法性檢查
   - **diagnostics**：產生 warnings，不阻止 startup

4. `assessLatestCookHandoffProposal()` 改成只輸出：
   - `none`
   - `usable`
   - `usable_with_warnings`

5. `parseCookHandoffCapsulesFromText()` 不再因為缺少 first-slice 欄位就直接丟掉 capsule

6. `buildContextProposalFromCookHandoffCapsule()` 改成 mission-level build；不再要求 implementation-ready

#### `extensions/completion/driver.ts`

7. 移除 `blockedFailureMessage` 在 startup path 的語義
   - `CookContextProposalResult` 改為：
     - `proposal?`
     - `warnings?: string[]`
     - `technicalFailureMessage?: string`

8. `runCookEntry()` 僅在技術性失敗時 early-return
   - 不再因語義性不足（acceptance wording / first-slice hints 缺失）early-return

### 這一階段完成後的結果

- main chat 討論清楚但 explicit handoff 不夠 slice-ready 的情況，仍可進 Start / Cancel
- `/cook` 不再因 `implementation_surfaces` / `verification_commands` 缺失而 fail closed

---

## Phase 1 — 建立統一 startup-intent pipeline

### 目標

把目前散在 `proposal.ts` / `index.ts` / `prompt-surfaces.ts` / `state-store.ts` 的 startup schema 收斂為單一路徑。

### 新增檔案

#### `extensions/completion/startup-intent.ts`

負責：

- 定義 `StartupIntentDraft` / `StartupIntentHints` / `StartupIntentDiagnostics`
- normalize legacy `cook_handoff`
- merge startup sources
- 建立 startup confirmation input model
- 將 startup draft 轉成 persisted startup brief payload

### 既有檔案調整

#### `extensions/completion/proposal.ts`

保留職責：

- recent discussion parsing
- mission normalization
- structured session extraction
- alternate mission handling
- workflow-context suppression logic

移除職責：

- explicit handoff 的 implementation-ready gate
- first-slice startup blocking policy

#### `extensions/completion/driver.ts`

- 刪除 local duplicate types，改從 `startup-intent.ts` 匯入共享型別
- 不再自己解釋 `ContextProposal` 是否 startable；只處理 draft / confirm / persist / dispatch

### 這一階段完成後的結果

- startup policy 的唯一 authority 變成 `startup-intent.ts`
- 型別不再在多個檔案中重複漂移

---

## Phase 2 — 將 `/cook` 入口改成單一路徑 synthesis

### 目標

不再讓 explicit handoff 成為先驗 gate，而是所有 `/cook` 都走同一條 startup synthesis pipeline。

### 關鍵重構

#### `extensions/completion/index.ts`

用新的單一入口取代：

- `deriveCookStartupProposal()`
- `deriveCookContextProposal()`

建議改成：

- `prepareCookStartupDraft()`

### 新流程

1. 收集 startup inputs：
   - inline `/cook` prompt
   - recent discussion entries
   - latest explicit assistant-authored `cook_handoff`（若存在）
   - canonical workflow context

2. 將 explicit handoff **結構化內容** 傳進 synthesis，而不是只帶失敗訊息

3. 同一個 synthesis 統一產生 `StartupIntentDraft`

4. 若 draft 存在，即進 Start / Cancel

5. 若 synthesize 完全失敗，才回 technical failure message

### 重要實作細節

- `stripCookHandoffBlocks()` 不應再用於 startup evidence 的唯一來源路徑
- explicit handoff 應先 parse 成 structured object，再與 recent discussion 一起交給 synthesizer
- `analyzeContextProposalWithAgent()` 若保留，需整合進新 pipeline；若不保留，應刪除

### 這一階段完成後的結果

- explicit handoff 不再能 block `/cook`
- weak capsule 會變成 input，而不是 fail reason

---

## Phase 3 — 重寫 primary-agent startup synthesis contract

### 目標

讓 primary agent 產出的東西是 mission-level startup draft，而不是 implementer-grade first slice contract。

### 關鍵程式

#### `extensions/completion/role-runner.ts`

重寫：

- `PRIMARY_AGENT_HANDOFF_SYSTEM_PROMPT`

建議調整為新的 startup synthesizer prompt，要求：

1. 產出 mission-level startup brief
2. first-slice hints 若明確可提供，否則可留空
3. 不要因 first slice 不夠細而拒絕輸出
4. 若 recent discussion 是 meta 討論，應 recover underlying repo-change mission
5. 若存在 explicit handoff，優先吸收其有價值內容，但不要被其弱 acceptance wording 綁死

### 建議 prompt 原則

- required:
  - `mission`
  - `scope`
  - `constraints/non_goals`
  - `acceptance`
  - `risks`
  - `notes`
- optional:
  - `first_slice_goal`
  - `implementation_surfaces`
  - `verification_commands`
  - `why_this_slice_first`
- diagnostics:
  - `warnings`
  - `needs_clarification`

### 額外清理

- `CONTEXT_PROPOSAL_ANALYST_SYSTEM_PROMPT` 與新的 startup synthesizer 若職責高度重疊，需合併或明確分工
- `driver.ts` 內 duplicate `ContextProposal*` type 應移除

---

## Phase 4 — 擴充 canonical startup brief，讓 hints 結構化

### 目標

不要再把 first-slice hints 塞進 `notes` 字串。

### 關鍵程式

#### `extensions/completion/prompt-surfaces.ts`

1. `AdvisoryStartupBrief` 加入 structured hint fields
2. confirmation UI 文案改成明確說明：
   - 這是在啟動 workflow，不是在批准 first slice exact contract
   - Start 後 `completion-regrounder` 會依 repo truth author slices
   - startup hints 僅為 advisory

#### `extensions/completion/state-store.ts`

3. `defaultStartupBrief()` 支援：
   - `first_slice_goal_hint`
   - `first_slice_non_goals_hint`
   - `implementation_surfaces_hint`
   - `verification_commands_hint`
   - `why_this_slice_first_hint`
   - `startup_confidence`
   - `needs_clarification`

4. `defaultState()` 仍保留：
   - `workflow_entry_status`
   - `workflow_entry_confirmed_at`
   - `workflow_session_id`
   - `startup_brief_path`

5. 規劃後續將 `state.json.advisory_startup_brief` 降級為 compatibility field，最終由 `.agent/current/startup-brief.json` 成為唯一 canonical startup source

### UX copy 建議

把類似：

- `Initialized completion control plane in ...`

逐步改成：

- `Started completion workflow for: <mission>.`
- `Saved canonical startup brief. completion-regrounder will derive the initial slice plan from repo truth.`

---

## Phase 5 — 將 slice 拆分責任完整移交 regrounder

### 目標

讓 `completion-regrounder` 明確承接：

- startup brief 轉 canonical slices
- clarification request when startup brief 不足以安全切 slice

### 關鍵檔案

#### `agents/completion-regrounder.md`

補充規則：

- `startup-brief.json` 是 mission-level intent，不是 slice plan
- `*_hint` 欄位全部只是 advisory
- 若 startup brief 不足以安全產生 first slice：
  - regrounder 進 `await_user_input`
  - 不要求 `/cook` 入口回 main chat 補 first-slice contract

#### `skills/completion-protocol/SKILL.md`

補充 shared rule：

- workflow entry 不由 first-slice readiness 決定
- `completion-regrounder` 是 canonical slice planning authority
- startup hints 僅供 reconciliation 參考

### 明確不變的地方

- `active-slice.json` 的 exact handoff requirement 不變
- `scripts/verify-completion-control-plane.js` 不放寬 selected/in_progress slice contract

---

## Phase 6 — driver 與 routing 收尾（讓 activation 更 canonical-state-first）

### 目標

減少 `/cook` 啟動後對 synthetic prompt / prompt-shape 的依賴。

### 關鍵程式

#### `extensions/completion/driver.ts`

- 重新評估 `queueCompletionDriverPrompt()` 是否可被直接 driver dispatch 取代
- 若 Pi API 允許，Start 後直接 dispatch workflow driver，而不是再 `sendUserMessage(COMPLETION WORKFLOW DRIVER...)`
- 若 Pi API 不允許，仍需保留 queued prompt，但授權必須只依 canonical active workflow state

#### `extensions/completion/index.ts`

整理：

- `isCompletionWorkflowSessionTurn()`
- `isCompletionWorkflowDispatchContext()`
- `hasStickyWorkflowContinuation()`

原則：

- workflow dispatch authorization 應以 canonical state 為主
- prompt shape detection 只能作為 attach / convenience heuristic，不應是 activation truth

### 這一階段的價值

這不是本次最先要解的 UX 問題，但它能讓 `/cook` 啟動後的體驗更穩定，並讓既有 `COOK_ENTRY_REDESIGN_PLAN.md` 真正收尾。

---

## Phase 7 — 文件、技能、測試、release gate 全面同步

### 必改文件

#### `README.md`

需改寫的核心語義：

- `/cook` 需要 enough context to synthesize a workflow startup brief
- first-slice hints are optional and advisory
- `completion-regrounder` derives canonical slices after Start
- fail-closed only for technical / confirmation / session-consistency reasons

#### `skills/cook-handoff-boundary/SKILL.md`

- 不再把 `first_slice_goal / implementation_surfaces / verification_commands` 當成 implementation-ready handoff 的 required entry fields
- ordinary chat 可在使用者要求時預覽 startup brief，但 preview 只作 startup intake，不是 exact slice contract

#### `CHANGELOG.md`

新增一版明確說明：

- `/cook` 入口從 implementation-ready startup gate 改成 workflow-entry synthesis
- explicit handoff 改為 high-priority input，而非 blocker

### 測試策略

#### `scripts/context-proposal-test.sh`

重寫重點：

- vague acceptance / missing implementation_surfaces 不再 fail closed
- explicit weak handoff 仍可產生 startup proposal snapshot
- weak capsule + strong main chat -> should start proposal flow

#### `scripts/smoke-test.sh`

更新 assertion：

- startup brief hints 以結構化欄位保存
- 不再要求 first-slice fields 是 startup blocker
- Start 後 state / startup-brief / plan / active-slice 仍正確 scaffold

#### `scripts/refocus-test.sh`

確保：

- active workflow replacement 仍然能比較 mission 並做 chooser
- explicit handoff 仍能作為 replacement proposal 的高權重輸入

#### `scripts/release-check.sh`

改掉所有舊敘述：

- 移除「`/cook` 期待 concrete first slice」相關字串
- 改成「`/cook` synthesizes and confirms startup brief, then regrounder authors slices」

#### 新增建議測試

1. `scripts/cook-startup-entry-test.sh`
   - meta-discussion + `/cook` 可進 startup confirmation
2. `scripts/cook-startup-hint-compat-test.sh`
   - legacy `cook_handoff` 缺 hint fields 仍可啟動
3. `scripts/cook-regrounder-clarification-test.sh`
   - startup brief 可 Start，但 regrounder 因資訊不足轉 `await_user_input`
4. `scripts/cook-driver-dispatch-test.sh`
   - canonical active state 下 completion role dispatch 不依賴 driver prompt shape

---

## 檔案級改動清單（落地版）

## 新增

### `extensions/completion/startup-intent.ts`

負責：

- startup draft schema
- hint / diagnostics schema
- legacy `cook_handoff` normalize
- source merge
- draft -> canonical startup brief transform

### `COOK_WORKFLOW_ENTRY_REFACTOR_PLAN.md`

- 作為這次重構的根目錄設計文件

---

## 修改

### `extensions/completion/proposal.ts`

- 讓 `CookHandoffCapsule` 的 first-slice 欄位 optional
- 移除 `fresh_but_not_startable` 的 blocking 語義
- 移除 `buildNonStartableCookHandoffMessage()`
- explicit handoff 改成 parse/diagnostic input
- 保留 mission normalization / alternate mission / workflow context suppression

### `extensions/completion/index.ts`

- 刪除或重寫 `deriveCookStartupProposal()`
- 刪除或重寫 `deriveCookContextProposal()`
- 新增單一路徑 `prepareCookStartupDraft()`
- same-entry synthesis 需吃到 structured explicit handoff，而不是只看 stripped transcript
- routing 僅在技術性失敗時回 `technicalFailureMessage`

### `extensions/completion/driver.ts`

- 移除 local duplicate `ContextProposal*` type
- `CookContextProposalResult` 改成 `proposal/warnings/technicalFailureMessage`
- `runCookEntry()` 不再因語義性不足 blocked
- 更新 Start/Cancel 後的使用者提示文字
- 規劃後續 direct dispatch 或更 state-first 的 kickoff path

### `extensions/completion/role-runner.ts`

- 重寫 `PRIMARY_AGENT_HANDOFF_SYSTEM_PROMPT`
- 規劃與 `CONTEXT_PROPOSAL_ANALYST_SYSTEM_PROMPT` 合併或重新分工
- output 目標改成 `StartupIntentDraft` 導向的 startup synthesis

### `extensions/completion/prompt-surfaces.ts`

- `AdvisoryStartupBrief` 加入 hint fields
- confirmation layout 文案改成 workflow-entry 語義
- 顯示 warnings / clarification hints，但不阻止 Start

### `extensions/completion/state-store.ts`

- `defaultStartupBrief()` 支援 structured hints / confidence / clarification
- `defaultState()` 仍保存 workflow entry fields
- 規劃減少 `state.json.advisory_startup_brief` 與 `startup-brief.json` 的重複

### `agents/completion-regrounder.md`

- 補 startup brief authority 與 clarification policy

### `skills/completion-protocol/SKILL.md`

- 補充 workflow-entry / startup-brief / regrounder authority 規則

### `skills/cook-handoff-boundary/SKILL.md`

- 更新 ordinary-chat preview / handoff 的語義與 required fields

### `README.md`

- 更新 `/cook` 產品規格與 typical examples

### `CHANGELOG.md`

- 記錄 entry policy 轉變

### `scripts/context-proposal-test.sh`
### `scripts/smoke-test.sh`
### `scripts/refocus-test.sh`
### `scripts/release-check.sh`

- 全面同步新語義

---

## 可能刪除 / 淘汰的舊結構

視實作結果，可逐步移除或降級：

- `buildNonStartableCookHandoffMessage()`
- `fresh_but_not_startable` proposal status
- `blockedFailureMessage` 作為語義性 startup gate
- `stripCookHandoffBlocks()` 在 startup synthesis 主路徑上的核心地位
- `driver.ts` 內 local duplicate proposal types
- 未使用或重複的 startup analyst 路徑（若被新的 startup synthesizer 完整取代）

---

## 重構後的驗收標準

以下條件成立，代表本次重構完成：

1. 使用者在 main chat 已把 mission 討論清楚後，輸入 `/cook`，即使 latest explicit handoff 缺少：
   - `first_slice_goal`
   - `implementation_surfaces`
   - `verification_commands`
   也仍能看到 Start / Cancel

2. `acceptance` 即使含有設計/討論語氣，只要整體 mission-level startup brief 仍清楚，就不會造成 `/cook failed closed`

3. Start 後 canonical `.agent/current/startup-brief.json` 會持久化 mission-level startup intent 與 optional hints

4. `completion-regrounder` 能根據 startup brief + repo truth author canonical slices；若資訊不足，會進 `await_user_input`

5. `active-slice.json` exact handoff contract 與 reviewer/auditor/stop-judge rubric contract 保持不變

6. README / skills / tests / release-check 全部反映新語義

7. `/cook` 的使用者訊息不再要求「回 main chat 把 first slice 與 verification 補齊」才能啟動 workflow

---

## 建議的提交順序

### Commit 1 — Policy pivot

- `proposal.ts`
- `driver.ts`
- 最小測試更新

目標：先解除「main chat 很清楚卻無法啟動 workflow」的 P0 問題。

### Commit 2 — Unified startup-intent schema

- 新增 `startup-intent.ts`
- `index.ts`
- `role-runner.ts`
- `prompt-surfaces.ts`
- `state-store.ts`

目標：把 startup synthesis 與 startup brief schema 收斂。

### Commit 3 — Regrounder authority + docs

- `agents/completion-regrounder.md`
- `skills/completion-protocol/SKILL.md`
- `skills/cook-handoff-boundary/SKILL.md`
- `README.md`
- `CHANGELOG.md`

### Commit 4 — Test/release parity

- `scripts/context-proposal-test.sh`
- `scripts/smoke-test.sh`
- `scripts/refocus-test.sh`
- `scripts/release-check.sh`
- 新增 startup-entry / regrounder-clarification regressions

### Commit 5 — Driver simplification (若本輪要做)

- `driver.ts`
- `index.ts`
- 相關 attach / auto-continue 測試

---

## 非目標

本次重構不打算：

- 允許 ordinary chat 直接 dispatch `completion_role`
- 取消 Start / Cancel confirm-first 邊界
- 讓 startup brief 取代 `plan.json` 或 `active-slice.json`
- 放寬 selected/in_progress active slice 的 exact handoff contract
- 重新設計 reviewer/auditor/stop-judge rubric model
- 將整個 completion workflow 併回單一 agent 直接實作

---

## 最終建議

以以下規則作為本次重構的唯一中心原則：

> **Explicit `/cook` always means “enter workflow-entry synthesis now”.**  
> **It must never be rejected solely because the first implementation slice is under-specified.**  
> **`completion-regrounder` remains the authority that converts startup intent plus repo truth into canonical slices.**

只要這個原則落地，現在最嚴重的 UX 問題就會消失：

- main chat 討論得很好卻無法啟動 workflow
- weak explicit handoff 反向阻止 `/cook`
- 系統把 workflow entry 誤當成 first-slice qualification gate
