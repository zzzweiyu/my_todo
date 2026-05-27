import Foundation
import TodoCore

struct WeeklyReportPromptBuilder {
    var systemInstructions: String {
        """
        你是一个资深项目周报编辑。输出必须忠于输入证据，不能编造负责人、日期、指标或外部事实。
        """
    }

    func sourceSummary(for summary: WeeklySummary) -> String {
        "基于 \(summary.completed.count) 个完成项、\(summary.blockers.count) 个卡点、\(summary.followUps.count) 个待跟进生成"
    }

    func prompt(for summary: WeeklySummary, variationSeed: String? = nil) -> String {
        """
        请基于下面的 MyTodo 本周任务证据，生成一份可直接发给团队或上级的中文周报草稿。

        写作要求：
        - 不要输出 Markdown 语法，不要使用 #、##、-、* 作为格式标记。
        - 只能输出三个段落标题：本周完成、卡点风险、下周跟进。
        - 必须忠于证据，只使用任务标题、项目路径和备注；不要编造负责人、日期、指标或外部事实。
        - 可以基于任务标题、项目路径和备注做适度归纳，把零散任务合并成自然的成果表达。
        - 本周完成：每条尽量写成“完成了什么 + 对项目有什么推进或交付价值”。
        - 卡点风险：写清“卡在哪里 + 可能影响什么 + 当前需要什么”，没有备注时不要硬编原因。
        - 下周跟进：写成具体动作，避免只重复任务名。
        - 每段 2-5 条，用 1. 2. 3. 编号；证据不足时写“暂无明确记录”，不要硬凑。
        - 保留关键任务名或项目路径，方便回看来源。
        \(variationInstruction(for: variationSeed))

        周期：\(summary.range.startDay) - \(summary.range.endDay)

        完成项：
        \(lines(for: summary.completed))

        卡点：
        \(lines(for: summary.blockers))

        待跟进：
        \(lines(for: summary.followUps))
        """
    }

    private func variationInstruction(for seed: String?) -> String {
        guard let seed, !seed.isEmpty else {
            return ""
        }

        return """
        - 本次生成批次：\(seed)。不要输出这个批次号；在忠于证据的前提下，尽量使用不同于上一版的组织角度和措辞。
        """
    }

    private func lines(for items: [WeeklyEvidenceItem]) -> String {
        guard !items.isEmpty else {
            return "- 无"
        }

        return items.map { item in
            let path = item.projectPath.map { "（\($0)）" } ?? "（临时任务）"
            let note = item.note.map { "：\($0)" } ?? ""
            return "- \(item.title)\(path)\(note)"
        }
        .joined(separator: "\n")
    }
}
