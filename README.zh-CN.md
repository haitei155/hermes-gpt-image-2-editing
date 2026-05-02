# Hermes GPT Image 2 Editing

为 Hermes Agent 添加一个面向源图的 GPT Image 2 图像编辑工具和配套 skill。

English documentation: [README.md](README.md)

这个项目适用于这样的 Hermes 配置：主对话模型使用第三方模型，例如 Kimi K2.6，但图像生成能力通过 Codex/OpenAI GPT Image 2 提供。它的目标是让 Hermes 在处理图生图、参考图编辑、局部修改时，把原图作为 `input_image` 传给 GPT Image 2，而不是先让文本模型描述原图，再靠提示词重新文生图。

## 提供内容

- `image_edit`：Hermes 工具，会通过 Codex/ChatGPT OAuth 后端把原图作为 `input_image` 传给 GPT Image 2。
- `gpt-image-2-editing`：Hermes skill，会要求 agent 在遇到图生图、改图、参考图编辑、局部修改、保留姿势/构图/身份特征等任务时优先调用 `image_edit`。
- 安装脚本会做少量可选 metadata patch，让 Hermes 的工具说明里也能看到 `image_edit`。

## 重要前置条件

你需要自己的 GPT Plus 账号，并且该账号需要可用 Codex。

安装这个项目之前，必须先在 Hermes 里完成 Codex 配置和登录，可以通过 Hermes WebUI，也可以用 CLI：

```bash
hermes auth codex
```

本项目不提供 OpenAI 账号、GPT Plus 订阅、Codex 权限、API Key，也不绕过任何账号要求。它只是复用 Hermes 已经登录好的 Codex 凭据。

## 为什么需要它

Hermes 内置的 `image_generate` 更偏向文生图。如果用户要求“基于这张图修改”，agent 可能会先描述原图，再把描述和修改要求拼成 prompt 交给 GPT Image 2 重新生成。这样很容易丢失姿势、构图、人脸相似度、服装细节、光照和背景结构。

本项目希望把链路变成：

```text
用户要求编辑已有图片
-> Hermes 加载 gpt-image-2-editing skill
-> Hermes 调用 image_edit(image_path, prompt, ...)
-> image_edit 把原图作为 input_image 传入
-> GPT Image 2 返回编辑后的图片
```

即使 Codex 后端拒绝某些严格编辑参数，fallback 路径仍会把源图传给模型；这不是纯文本重绘。

## 适用场景

- 基于已有图片做编辑，而不是只靠文字重新生成。
- 需要尽量保留原图姿势、镜头角度、构图、人脸身份、背景结构的图生图。
- 替换衣服、发型、道具、背景、物体、颜色或风格。
- 角色/cosplay 转换，但希望原图构图和人物姿态仍然接近。
- Hermes 主模型使用第三方 API，但希望图像生成和编辑由 Codex/OpenAI GPT Image 2 负责。
- 飞书、QQ、Telegram、Slack 等 Hermes 网关场景下复用同一套图片编辑能力。

不适用于：

- 没有源图的纯文生图。请继续使用 Hermes `image_generate`。
- 精确到像素的 Photoshop 式确定性编辑。这仍然是模型编辑，不是传统图像软件。
- 未考虑 Codex/OpenAI 账号限制的大规模批处理任务。

## 安装

在运行 Hermes 的机器上执行：

```bash
git clone https://github.com/haitei155/hermes-gpt-image-2-editing.git
cd hermes-gpt-image-2-editing
./install.sh
```

如果你通过飞书、QQ、Telegram、Slack、Discord 等平台使用 Hermes，安装后重启 gateway：

```bash
systemctl restart hermes-gateway
```

如果只是本地 CLI 使用，安装后开启新的 Hermes 会话即可。

## 验证

```bash
cd ~/.hermes/hermes-agent
python - <<'PY'
from tools.registry import discover_builtin_tools, registry
discover_builtin_tools()
entry = registry.get_entry("image_edit")
print("image_edit registered:", bool(entry))
if entry:
    print(entry.toolset, entry.schema["description"])
PY
```

预期看到：

```text
image_edit registered: True
```

也可以确认 skill 是否存在：

```bash
hermes skills list | grep gpt-image-2-editing
```

## 示例提示词

```text
Use image_edit. Edit /root/.hermes/image_cache/source.png.
Preserve the original pose, camera angle, face identity, lighting direction, and main background.
Change the outfit into Fate Rider Medusa's outfit, change the hair to a purple cosplay wig,
replace the yellow pom-poms with silver chained daggers, and remove the Blue Archive halo.
```

agent 应该优先调用：

```text
image_edit(
  image_path="/root/.hermes/image_cache/source.png",
  prompt="Edit the provided source image. Preserve ... Change ...",
  aspect_ratio="portrait",
  input_fidelity="high"
)
```

## 卸载

```bash
./uninstall.sh
systemctl restart hermes-gateway
```

## License

Apache License 2.0.
