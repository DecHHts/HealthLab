# HealthLab 体检记

拍照或导入医院化验报告截图，自动识别全部检测项目并按时间记录；同一项目可以看历次趋势，也能以「项目 × 日期」表格查看和导出。数据只保存在手机本地。

## 功能（M1）

- 导入：相册多选、扫描纸质报告（自动矫正）、从文件选择
- 识别：iPhone 自带的 Vision 文字识别（端侧，不联网）+ `LabParser` 解析器，提取项目名称、缩写、结果、↑↓、单位、参考范围、检验方法，以及采集时间、标本编号、医院等
- 核对：识别结果与原图对照，逐行修改、删除、添加；同一报告的多页截图可合并；相同标本编号会提示重复
- 报告：按年份浏览，异常项数量一目了然
- 趋势：每个项目的折线图 + 参考上下限、较上次变化、最高/最低/平均
- 表格：项目 × 体检日期，按分类筛选、只看有异常的项目、搜索；导出 CSV（Excel 可直接打开）

## 在 iPhone 上运行

需要一台装有 Xcode 16 或更新版本的 Mac。

```sh
brew install xcodegen
git clone https://github.com/DecHHts/HealthLab.git
cd HealthLab
xcodegen generate
open HealthLab.xcodeproj
```

在 Xcode 里选中 HealthLab target → Signing & Capabilities → Team 选择你的 Apple ID（免费账号即可），把 iPhone 连上 Mac，点运行。免费账号安装的 App 7 天后需要重新运行一次。

## 结构

| 路径 | 内容 |
| --- | --- |
| `Packages/LabParser` | 纯 Swift 的报告解析器，不依赖 UI，可用 `swift test` 单独测试 |
| `HealthLab/Models` | SwiftData 数据模型：报告、检测结果、原图 |
| `HealthLab/Services` | OCR、识别草稿与保存、指标汇总、CSV 导出 |
| `HealthLab/Views` | 界面：报告、核对、趋势、表格 |
| `project.yml` | XcodeGen 工程配置 |

## 识别不准时

解析器针对「序号 | 项目名称 (缩写) | 结果 | 单位 | 参考值 | 检验方法」的常见版式。遇到识别不好的新医院版式，把截图发给开发者，加进 `ReportParserTests` 的样例里再调整解析规则。

计划文档：[体检报告记录 App：产品与技术计划](https://claude.ai/artifact/W3yzT7B3wi2j6qznAmrnJq)
