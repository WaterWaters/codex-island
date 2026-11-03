# 第三方内容与素材边界

项目自产源码、文档和原创 SVG 设计示意采用 [MIT](LICENSE)。公开仓库及打包产物不包含个人自定义宠物图片，也不包含 Codex 内置宠物 WebP、完整安装包或完整应用脚本。

项目品牌图标 `Artwork/AppIcon.png`、`Artwork/AppIcon.icns` 和 `docs/assets/banner.png` 由内置图像生成工具根据“猫、水元素、Water、Codex”创意生成，作为本项目 MIT 内容提供。它们是新绘制的抽象品牌图形，不使用私人宠物原图，也不属于可选择的运行时宠物资产。生成提示词与用途见 [品牌说明](Artwork/README.md)。

- 默认展示系统提供的 `cat.fill` 图标，由系统渲染，不复制图标图片进仓库。系统图标不属于本项目 MIT 授权内容。
- 用户选择内置宠物后，只读本机已安装 Codex 的所选资产及共享时长。第三方图片归各自权利人所有，本项目未取得或转授其再分发许可。
- 测试用精灵图由测试代码生成匿名几何色块，不使用个人素材。解析测试仅包含小型合成字面量，不加载或执行 Codex 脚本。
- Codex 名称用于说明兼容对象及系统应用查找，不代表 OpenAI 官方产品、认可或合作。
- Claude / Claude Code 名称用于说明兼容对象及系统应用查找，不代表 Anthropic 官方产品、认可或合作。本项目不随包分发 Claude 应用或会话数据。
- Atoll 仅作视觉方向参考；未将其代码或资产作为本工程依赖，本项目 MIT 不适用于 Atoll。

- `Sources/CodexIsland/Resources/Brand/ProviderIcons/claude.svg` 与 `openai.svg` 为岛内当前来源的身份识别展示。图形与名称权利归 Anthropic P. C. 与 OpenAI 各自所有，本项目未取得再分发授权、不主张对其任何权利，引用只服务于用户识别已安装的来源应用，不构成官方产品、认可或合作。（2026-11-03 经用户决定入库随包，Codex 来源的展示图标按用户指示采用 OpenAI/ChatGPT 花结标。来源与裁剪细节见该目录 [PROVENANCE.md](Sources/CodexIsland/Resources/Brand/ProviderIcons/PROVENANCE.md)。）

个人素材、包含它们的预览及私人开发记录保存在本机被忽略的 `local/` 中，不参与 SwiftPM 资源、测试和打包。公开源码和文档不应链接这些文件。请勿强制添加被忽略的目录，或上传整个工作目录压缩包。
