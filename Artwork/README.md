# 品牌图形

- `AppIcon.png`：1024 × 1024，透明外沿，可用于项目头像。
- `AppIcon.icns`：App 图标容器，包含 16–1024px 及 Retina 尺寸，打包脚本自动携带。
- `../docs/assets/banner.png`：2172 × 724，README 横幅，已接入首页。

创意：抽象水猫 + 代码提示符 `>_` + W 形水波，横幅仅显示 Codex Island；Water 以水元素和 W 形水波表达。两图使用内置 image_gen 生成，图标的缩放与 ICNS 封装使用本机格式工具；没有使用私人宠物图片。项目按根目录 MIT 许可提供这些新品牌资产；Codex 名称仅说明兼容对象，不代表官方产品。

## 图标生成提示词

```text
Use case: logo-brand.
Asset type: finished macOS app icon and GitHub project avatar for "Codex Island" by Water.
Create ONE square 1024x1024 icon, not a mockup or a contact sheet.
Subject: an original, beautifully simple aquatic cat emblem. The cat's head has two clear ears and an elegant curved tail/body made from a single flowing water-droplet shape. Integrate a crisp terminal prompt >_ as the cat's facial feature/chest using negative space, clearly suggesting Codex and coding. A flowing W-like wave under the cat subtly evokes the creator Water. This is an abstract invented cat, not a photograph, pet portrait or any existing character.
Style: precise sculpted logo, strong memorable silhouette, restrained translucent aqua glass with clean luminous edges and subtle depth. Readable at 32 pixels; a few bold shapes, no tiny decorations.
Composition: centered emblem occupying about 65% of the canvas within a dark midnight-blue macOS squircle tile; tile occupies 90% of square canvas. Soft elegant sea-cyan illumination and deep ink contrast, quiet premium developer-tool aesthetic. Entire tile visible, straight front view.
Background: truly transparent outside the squircle tile, clean alpha. No fake checkerboard, no white surround.
Constraints: no letters or words other than the small symbolic >_; no OpenAI knot, no official Codex logo, no private pet, no watermark, no added objects, no pedestal, no photographic scenery. Deliver the production icon itself.
```

## Banner 生成提示词（初版）

使用先生成的图标作为品牌参考，不使用私人图片。

```text
Use case: ads-marketing / logo-brand.
Asset type: finished wide GitHub README banner for the independent macOS developer app Codex Island by Water.
Input image 1 is the BRAND AND CHARACTER REFERENCE, not an edit target. Create a NEW extra-wide 3:1 horizontal banner, about 2400x800.
Preserve the original aquatic cat logo identity from the reference: translucent aqua glass cat ears/head, white terminal >_ face, curling water tail/body and W-shaped flowing wave. Use a large clean rendition of this same emblem at the right side, WITHOUT its app-icon squircle frame. Do not replace with a photographic or furry cat.
Layout: confident editorial spacing, oversized immaculate typography on the left half, emblem on the right half. Left-aligned title with exact text "Codex Island", large, very legible refined modern sans serif in soft white. Below it smaller exact text "Water", in bright clear aqua with generous letter spacing. Only these two text strings, no other text. Respect a generous safe margin on all edges. Text must be accurate: C-o-d-e-x space I-s-l-a-n-d; W-a-t-e-r.
Background: full-bleed deep midnight ink-blue, with a few subtle water ripples and one graceful luminous cyan wave connecting the left and right. Restrained glass highlights, sophisticated premium macOS tool identity, strong contrast, ample quiet space around type. A hint of a water island underneath the cat is fine; no elaborate scenery.
Constraints: one complete banner, not a mockup/contact sheet. No private pet, no real cat photo, no official OpenAI knot, no extra slogans, no random code text, no watermark, no UI chrome. Opaque full-bleed backdrop.
```


## Banner 文案更新

2026-10-22：按要求移除 Water 字样，保留 Codex Island 标题与原有水猫 / 水波。使用内置 image_gen 对原图编辑，更新后的文件仍为 docs/assets/banner.png。

```text
Use case: precise-object-edit. Edit the supplied Codex Island README banner. Remove ONLY the cyan word 'Water' beneath the large white title on the left, naturally reconstructing the same dark midnight-blue background and subtle water lighting behind those five letters. Preserve the exact existing 'Codex Island' title, its typography, size and position, the aquatic glass cat with >_ face on the right, all waves, colors, lighting, composition, aspect ratio and framing. Do not add any text or objects. The ONLY visible text in the finished banner must be 'Codex Island'. Keep an opaque full-bleed background.
```
