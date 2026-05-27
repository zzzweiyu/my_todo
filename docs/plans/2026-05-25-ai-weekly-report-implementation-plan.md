# AI Weekly Report Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the AI weekly report feature described in `docs/ai-weekly-report-prd.html`: a weekly task view, lightweight report metadata on tasks, and an editable AI-generated Markdown weekly report draft.

**Architecture:** Extend `TodoCore` first with report metadata, week-range aggregation, and persistence-compatible decoding. Then add SwiftUI surfaces in small layers: shared tagging UI, the new weekly panel, and the report draft workflow. Keep the AI service behind a protocol so tests can use a fake client and the UI can show deterministic loading/error states.

**Tech Stack:** Swift 6, SwiftUI, Combine, local JSON persistence, macOS Keychain via Security framework, URLSession-based AI client, existing `TodoCoreChecks` executable tests.

---

## Task 1: Core Report Metadata And Week Aggregation

**Files:**
- Modify: `Sources/TodoCore/TodoItem.swift`
- Modify: `Sources/TodoCore/Project.swift`
- Modify: `Sources/TodoCore/TodoDatabase.swift`
- Modify: `Sources/TodoCore/TodoStore.swift`
- Test: `Tests/TodoCoreChecks/main.swift`

**Steps:**
1. Add a public `WeeklyReportStatus: String, Codable, CaseIterable, Sendable` enum with `normal`, `blocker`, and `followUp`.
2. Add `weeklyReportStatus` and `weeklyReportNote` to `TodoItem` and `ProjectStep`, defaulting to `.normal` and `nil`.
3. Add custom decoding defaults so existing JSON files without the new fields continue to load.
4. Add store APIs to update report metadata for a todo and for a project step; linked todo/step pairs must stay in sync.
5. Add a `WeekRange` value and Monday-to-Sunday calculation using the current calendar/time zone.
6. Add a weekly summary API that returns completed, open, blocker, and follow-up evidence items with project paths.
7. Add tests for legacy decoding, metadata sync, week boundaries, completed-by-`completedAt`, and cross-week exclusion.
8. Run `swift run TodoCoreChecks` and verify all checks pass.
9. Commit: `feat: add weekly report metadata model`.

## Task 2: Shared Task Report Tagging UI

**Files:**
- Create: `Sources/MyTodo/Views/WeeklyReportTagEditorView.swift`
- Modify: `Sources/MyTodo/Views/TodoRowView.swift`
- Modify: `Sources/MyTodo/Views/TodayPanelView.swift`
- Modify: `Sources/MyTodo/Views/ProjectsPanelView.swift`

**Steps:**
1. Create a reusable editor for `普通 / 卡点 / 待跟进` plus a one-line report note.
2. Add a compact status indicator to today task rows and project step rows.
3. Wire the editor from both today tasks and project steps using store metadata update APIs.
4. Keep the default row height stable when no metadata is shown.
5. Add empty-note behavior: trimming whitespace stores `nil`.
6. Manually verify that linked project steps and today items show the same report status.
7. Run `swift build`.
8. Commit: `feat: add weekly report tagging UI`.

## Task 3: Weekly Panel View

**Files:**
- Create: `Sources/MyTodo/Views/WeekPanelView.swift`
- Modify: `Sources/MyTodo/Views/TodoPanelView.swift`
- Modify: `Sources/TodoCore/TodoStore.swift`

**Steps:**
1. Add a `.week` tab titled `本周` to the existing segmented picker.
2. Build the weekly header with date range and previous/next week controls.
3. Add metric cards for completed count, blocker count, follow-up count, and completion rate.
4. Add grouped evidence lists for `待完成`, `卡点`, `待跟进`, and `已完成`.
5. Keep the panel width aligned with the existing 380px menu bar layout.
6. Add empty states for weeks with no tasks and groups with no evidence.
7. Wire the primary `生成 AI 周报` action to a placeholder draft entry point until the AI workflow is added.
8. Run `swift build` and manually inspect the menu bar panel.
9. Commit: `feat: add weekly task panel`.

## Task 4: Keychain And AI Client Boundary

**Files:**
- Create: `Sources/MyTodo/Services/APIKeyStore.swift`
- Create: `Sources/MyTodo/Services/WeeklyReportAIClient.swift`
- Create: `Sources/MyTodo/Services/WeeklyReportPromptBuilder.swift`
- Modify: `Package.swift` if Security linking requires explicit linker settings.
- Test: `Tests/TodoCoreChecks/main.swift` or a new lightweight checks target if UI target tests are added.

**Steps:**
1. Add a Keychain-backed model provider configuration store using `kSecClassGenericPassword`.
2. Add a small settings/config surface for choosing OpenAI/阿里云百炼/阿里云 Coding Plan/DeepSeek, editing model name and service address, and saving, replacing, or deleting the API key.
3. Define `WeeklyReportAIClientProtocol` with an async `generate(context:)` method.
4. Implement prompt/context building from weekly evidence; require the model to output only the three Markdown sections.
5. Implement URLSession AI client behind the protocol, with OpenAI Responses API and OpenAI-compatible chat completions support for 阿里云百炼、阿里云 Coding Plan and DeepSeek.
6. Add fake-client tests for prompt context shape and failure handling where feasible.
7. Verify the app does not write model provider configuration or API key to `tasks.json`.
8. Run `swift build`.
9. Commit: `feat: add weekly report AI client boundary`.

## Task 5: Report Draft Workflow

**Files:**
- Create: `Sources/MyTodo/Views/WeeklyReportDraftView.swift`
- Modify: `Sources/MyTodo/Views/WeekPanelView.swift`
- Modify: `Sources/TodoCore/TodoDatabase.swift`
- Modify: `Sources/TodoCore/TodoStore.swift`
- Test: `Tests/TodoCoreChecks/main.swift`

**Steps:**
1. Add a `WeeklyReportDraft` model keyed by week start date so `保存草稿` can persist safely.
2. Add store APIs to save and load the draft for a week.
3. Present a modal/sheet with source summary, editable Markdown text, evidence list, and actions.
4. Support `重新生成` without overwriting user-edited text until the new output is accepted.
5. Support `复制 Markdown` via `NSPasteboard`.
6. Show `复制前请确认内容准确` in the draft surface.
7. Preserve current draft and task data on network/API errors.
8. Add tests for draft persistence and week-key isolation.
9. Run `swift run TodoCoreChecks` and `swift build`.
10. Commit: `feat: add weekly report draft workflow`.

## Task 6: End-To-End Verification And PRD Alignment

**Files:**
- Modify: `docs/ai-weekly-report-prd.html` only if implementation discoveries require small clarifications.
- Optional: `docs/plans/2026-05-25-ai-weekly-report-implementation-plan.md`

**Steps:**
1. Create a sample week with completed tasks, blockers, follow-ups, and open items.
2. Verify Monday-to-Sunday filtering and previous/next week navigation.
3. Verify metadata edits from today and project views stay synchronized.
4. Verify missing API key, invalid key, network failure, and successful fake-client generation states.
5. Verify Markdown output contains exactly `本周完成`, `卡点风险`, and `下周跟进`.
6. Verify copy, save draft, reload app, and reopen draft.
7. Run `swift run TodoCoreChecks`.
8. Run `swift build`.
9. Review `git diff` for unrelated changes before finishing.
10. Commit: `test: verify AI weekly report workflow`.

## MyTodo Display Version

Use this as the project tree in the app:

- AI 周报与周任务视图开发
  - 1. 核心数据模型与周聚合
    - 增加周报状态和备注字段
    - 兼容旧 JSON 解码
    - 实现周一到周日范围计算
    - 实现本周证据聚合 API
    - 补充 TodoCoreChecks
  - 2. 周报标记交互
    - 新建周报标记编辑器
    - 今天任务行显示标记状态
    - 项目步骤行显示标记状态
    - 同步 linked todo 和 step 元数据
    - 手动验证标记编辑
  - 3. 本周任务视图
    - 新增本周顶层 tab
    - 展示日期范围和周切换
    - 展示完成/卡点/跟进/完成率指标
    - 按状态分组任务证据
    - 接入生成 AI 周报入口
  - 4. Keychain 与 AI 边界
    - 实现大模型厂商/API Key Keychain 存储
    - 添加 OpenAI/阿里云百炼/阿里云 Coding Plan/DeepSeek 厂商选择与模型配置入口
    - 定义 AI client protocol
    - 构建三段式 Markdown prompt
    - 处理未配置/鉴权/网络错误
  - 5. 周报草稿流程
    - 新增周报草稿模型
    - 实现草稿保存和读取
    - 构建可编辑草稿弹层
    - 支持重新生成和复制 Markdown
    - 保证失败不覆盖已有草稿
  - 6. 端到端验收
    - 验证自然周统计
    - 验证标记同步
    - 验证 AI 成功和失败状态
    - 验证复制和保存草稿
    - 运行 TodoCoreChecks 和 swift build
