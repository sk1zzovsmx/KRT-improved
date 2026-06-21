# WotLK 3.3.5a Interface Texture Catalog

Generated from static `Interface\...` texture references in the 3.3.5a FrameXML mirror,
commit `d0339b1`. This is a development reference for KRT UI work; it does not copy,
convert, or redistribute Blizzard BLP assets.

Scope notes:

- Paths below are client texture paths that WoW resolves from MPQ data at runtime.
- Omit `.blp` in XML and Lua, matching Blizzard/KRT usage.
- This is not a full MPQ listfile dump; it is the static path set referenced by FrameXML Lua/XML.
- Some texture sheets need `TexCoords` to isolate the intended slice.
- For a true visual audit, load the path in a client-side frame; Markdown cannot render BLP paths.

## Reusable Mixin And XML Template

Use this as a dev-only preview pattern when you want an in-game wall of texture blocks. Keep it out
of release UI unless a feature actually needs it.

```xml
<Button name="KRTTextureCatalogBlockTemplate" virtual="true" enableMouse="true">
    <Size>
        <AbsDimension x="180" y="54" />
    </Size>
    <Layers>
        <Layer level="BACKGROUND">
            <Texture name="$parentBg" file="Interface\Buttons\WHITE8x8">
                <Anchors>
                    <Anchor point="TOPLEFT" />
                    <Anchor point="BOTTOMRIGHT" />
                </Anchors>
                <Color r="0.02" g="0.02" b="0.02" a="0.88" />
            </Texture>
        </Layer>
        <Layer level="ARTWORK">
            <Texture name="$parentPreview">
                <Size>
                    <AbsDimension x="36" y="36" />
                </Size>
                <Anchors>
                    <Anchor point="LEFT">
                        <Offset><AbsDimension x="8" y="0" /></Offset>
                    </Anchor>
                </Anchors>
            </Texture>
            <FontString name="$parentLabel" inherits="GameFontNormalSmall" justifyH="LEFT">
                <Size><AbsDimension x="126" y="36" /></Size>
                <Anchors>
                    <Anchor point="LEFT" relativeTo="$parentPreview" relativePoint="RIGHT">
                        <Offset><AbsDimension x="8" y="0" /></Offset>
                    </Anchor>
                </Anchors>
            </FontString>
        </Layer>
    </Layers>
    <HighlightTexture file="Interface\QuestFrame\UI-QuestTitleHighlight" alphaMode="ADD" />
</Button>
```

```lua
local TextureCatalogBlockMixin = {}

function TextureCatalogBlockMixin:SetTexturePath(path, label, texCoords)
    self.path = path
    self.preview:SetTexture(path)
    if texCoords then
        self.preview:SetTexCoord(unpack(texCoords))
    else
        self.preview:SetTexCoord(0, 1, 0, 1)
    end
    self.label:SetText(label or path)
end

function TextureCatalogBlockMixin:BindTooltip()
    self:SetScript("OnEnter", function(block)
        GameTooltip:SetOwner(block, "ANCHOR_RIGHT")
        GameTooltip:SetText(block.path or "", 1, 1, 1)
        GameTooltip:Show()
    end)
    self:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
```

Expected Lua acquisition for a block created with the XML template:

```lua
local block = CreateFrame("Button", "KRTDevTextureBlock1", parent, "KRTTextureCatalogBlockTemplate")
block.preview = _G[block:GetName() .. "Preview"]
block.label = _G[block:GetName() .. "Label"]
for key, value in pairs(TextureCatalogBlockMixin) do
    block[key] = value
end
block:BindTooltip()
block:SetTexturePath("Interface\\Buttons\\UI-ActionButton-Border", "Action button border")
```

## Visual Block Catalog

Each entry is intended to become one preview block with a 36x36 texture sample and the path as
tooltip text. For sheets, preview the full sheet first, then add `TexCoords` when choosing a slice.

For actual Windows-side visual previews, run the local BLP-to-JPEG generator. It reads an extracted
`Interface` folder, converts BLP files to JPEG thumbnails, and writes a browser gallery outside the
release addon files. The script requires Pillow with BLP support; this Codex desktop runtime already
provides it.

```text
C:\Users\ferra\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe ^
  tools\build-interface-texture-catalog.py ^
  --source C:\Users\ferra\Desktop\WoW_Interface_AddOn_Kit_3.3.5a\Interface ^
  --output .codex\local-interface-texture-catalog
```

Open `.codex\local-interface-texture-catalog\index.html` to inspect the visual catalog.
The generated JPEG files are local inspection artifacts and should not be redistributed.

### Dialog and window skins

Backdrop and chrome pieces for Blizzard-style windows and dialogs.

- Block `36x36`: `Interface\DialogFrame\UI-DialogBox-Background-Dark`
  - Source: `RaidFrame.xml`
  - Source: `UIDropDownMenuTemplates.xml`
- Block `36x36`: `Interface\DialogFrame\UI-DialogBox-Border`
  - Source: `BNConversations.xml`
  - Source: `BNet.xml`
  - Additional refs: 21
- Block `36x36`: `Interface\DialogFrame\UI-DialogBox-Header`
  - Source: `BNConversations.xml`
  - Source: `Blizzard_BindingUI/Blizzard_BindingUI.xml`
  - Additional refs: 13
- Block `36x36`: `Interface\DialogFrame\UI-DialogBox-Corner`
  - Source: `Blizzard_BattlefieldMinimap/Blizzard_BattlefieldMinimap.xml`
  - Source: `Blizzard_Calendar/Blizzard_CalendarTemplates.xml`
  - Additional refs: 6
- Block `36x36`: `Interface\CharacterFrame\UI-Party-Background`
  - Source: `Blizzard_ArenaUI/Blizzard_ArenaUI.xml`
  - Source: `PartyFrame.xml`
- Block `36x36`: `Interface\Tooltips\UI-Tooltip-Background`
  - Source: `AutoComplete.xml`
  - Source: `Blizzard_Calendar/Blizzard_Calendar.xml`
  - Additional refs: 22
- Block `36x36`: `Interface\Tooltips\UI-Tooltip-Border`
  - Source: `AutoComplete.xml`
  - Source: `BNConversations.xml`
  - Additional refs: 27

### Buttons and button states

Normal, pushed, disabled, highlight, plus/minus, checkbox, quickslot, and action button pieces.

- Block `36x36`: `Interface\Buttons\UI-Panel-Button-Up`
  - Source: `BasicControls.xml`
  - Source: `Blizzard_ItemSocketingUI/Blizzard_ItemSocketingUI.xml`
  - Additional refs: 1
- Block `36x36`: `Interface\Buttons\UI-Panel-Button-Down`
  - Source: `BasicControls.xml`
  - Source: `UIPanelTemplates.xml`
- Block `36x36`: `Interface\Buttons\UI-Panel-Button-Highlight`
  - Source: `BasicControls.xml`
  - Source: `UIPanelTemplates.xml`
- Block `36x36`: `Interface\Buttons\UI-Panel-Button-Disabled`
  - Source: `UIPanelTemplates.xml`
- Block `36x36`: `Interface\Buttons\UI-PlusButton-Up`
  - Source: `FriendsFrame.xml`
- Block `36x36`: `Interface\Buttons\UI-MinusButton-Up`
  - Source: `FriendsFrame.xml`
- Block `36x36`: `Interface\Buttons\UI-CheckBox-Up`
  - Source: `Blizzard_AchievementUI/Blizzard_AchievementUI.xml`
  - Source: `ChatConfigFrame.xml`
  - Additional refs: 6
- Block `36x36`: `Interface\Buttons\UI-CheckBox-Check`
  - Source: `Blizzard_AchievementUI/Blizzard_AchievementUI.xml`
  - Source: `Blizzard_TokenUI/Blizzard_TokenUI.xml`
  - Additional refs: 9
- Block `36x36`: `Interface\Buttons\UI-Quickslot2`
  - Source: `ActionButtonTemplate.xml`
  - Source: `Blizzard_AuctionUI/Blizzard_AuctionUITemplates.xml`
  - Additional refs: 8
- Block `36x36`: `Interface\Buttons\UI-ActionButton-Border`
  - Source: `ActionButtonTemplate.xml`

### Rows, highlights, and selection fills

Reusable highlight strips and list-row backgrounds for dense KRT tables.

- Block `36x36`: `Interface\QuestFrame\UI-QuestTitleHighlight`
  - Source: `ChannelFrame.xml`
  - Source: `FloatingChatFrame.xml`
  - Additional refs: 8
- Block `36x36`: `Interface\Buttons\UI-ListBox-Highlight`
  - Source: `Blizzard_DebugTools/Blizzard_DebugTools.xml`
- Block `36x36`: `Interface\Buttons\UI-Listbox-Highlight2`
  - Source: `ArenaFrame.xml`
  - Source: `BattlefieldFrame.xml`
  - Additional refs: 4
- Block `36x36`: `Interface\Buttons\UI-Common-MouseHilight`
  - Source: `ArenaRegistrarFrame.xml`
  - Source: `BNConversations.xml`
  - Additional refs: 22
- Block `36x36`: `Interface\AuctionFrame\UI-AuctionItemNameFrame`
  - Source: `Blizzard_AuctionUI/Blizzard_AuctionUITemplates.xml`
- Block `36x36`: `Interface\FriendsFrame\UI-FriendsFrame-HighlightBar`
  - Source: `Blizzard_AchievementUI/Blizzard_AchievementUI.xml`
  - Source: `Blizzard_Calendar/Blizzard_CalendarTemplates.xml`
  - Additional refs: 2

### Icons and item slots

Square icon placeholders, inventory slots, paperdoll slots, and icon overlays.

- Block `36x36`: `Interface\Buttons\UI-EmptySlot`
  - Source: `Blizzard_MacroUI/Blizzard_MacroUI.xml`
  - Source: `Blizzard_TrainerUI/Blizzard_TrainerUI.xml`
  - Additional refs: 4
- Block `36x36`: `Interface\Buttons\UI-EmptySlot-White`
  - Source: `MailFrame.xml`
  - Source: `TalentFrameTemplates.xml`

### Raid, target, and unit visuals

Target frame pieces, raid target icons, raid UI pieces, and group frame surfaces.

- Block `36x36`: `Interface\TargetingFrame\UI-TargetingFrame`
  - Source: `PlayerFrame.xml`
  - Source: `TargetFrame.xml`
- Block `36x36`: `Interface\TargetingFrame\UI-StatusBar`
  - Source: `AlternatePowerBar.xml`
  - Source: `AudioOptionsPanels.xml`
  - Additional refs: 16

### Chat and edit surfaces

Chat tabs, chat frame chrome, editbox pieces, and chat button states.

- Block `36x36`: `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up`
  - Source: `FloatingChatFrame.xml`
- Block `36x36`: `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down`
  - Source: `FloatingChatFrame.xml`
- Block `36x36`: `Interface\ChatFrame\UI-ChatInputBorder-Left`
  - Source: `ArenaRegistrarFrame.xml`
  - Source: `GuildRegistrarFrame.xml`
  - Additional refs: 2
- Block `36x36`: `Interface\ChatFrame\UI-ChatInputBorder-Right`
  - Source: `ArenaRegistrarFrame.xml`
  - Source: `GuildRegistrarFrame.xml`
  - Additional refs: 2
- Block `36x36`: `Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up`
  - Source: `Blizzard_AchievementUI/Blizzard_AchievementUI.xml`
  - Source: `Blizzard_Calendar/Blizzard_Calendar.xml`
  - Additional refs: 5
- Block `36x36`: `Interface\ChatFrame\UI-ChatIcon-Minimize-Up`
  - Source: `FloatingChatFrame.xml`

### Minimap and tracking

Minimap border, tracking, zoom, clock, and small circular button textures.

- Block `36x36`: `Interface\Minimap\UI-Minimap-Border`
  - Source: `Blizzard_GMChatUI/Blizzard_GMChatUI.xml`
  - Source: `Minimap.xml`
- Block `36x36`: `Interface\Minimap\UI-Minimap-ZoomButton-Highlight`
  - Source: `GameTime.xml`
  - Source: `Minimap.xml`
  - Additional refs: 1
- Block `36x36`: `Interface\Minimap\UI-Minimap-Background`
  - Source: `Minimap.xml`
  - Source: `TotemFrame.xml`
  - Additional refs: 1
- Block `36x36`: `Interface\Minimap\MiniMap-TrackingBorder`
  - Source: `Minimap.xml`
  - Source: `VoiceChat.xml`

### Bars, casting, and status

Status-bar and cast-bar strips useful as fills or separators.

- Block `36x36`: `Interface\TargetingFrame\UI-StatusBar`
  - Source: `AlternatePowerBar.xml`
  - Source: `AudioOptionsPanels.xml`
  - Additional refs: 16
- Block `36x36`: `Interface\CastingBar\UI-CastingBar-Border`
  - Source: `CastingBarFrame.xml`
  - Source: `MirrorTimer.xml`
- Block `36x36`: `Interface\CastingBar\UI-CastingBar-Flash`
  - Source: `CastingBarFrame.xml`
- Block `36x36`: `Interface\PaperDollInfoFrame\UI-Character-Skills-Bar`
  - Source: `Blizzard_AchievementUI/Blizzard_AchievementUI.xml`
  - Source: `Blizzard_InspectUI/InspectHonorFrame.xml`
  - Additional refs: 5

### Money, loot, and merchant UI

Coin, loot roll, merchant, and inventory-related UI pieces.

- Block `36x36`: `Interface\Buttons\UI-GroupLoot-Dice-Up`
  - Source: `LootFrame.xml`
- Block `36x36`: `Interface\Buttons\UI-GroupLoot-Coin-Up`
  - Source: `LootFrame.xml`
- Block `36x36`: `Interface\MerchantFrame\UI-Merchant-RepairIcons`
  - Source: `MerchantFrame.xml`
- Block `36x36`: `Interface\ContainerFrame\UI-Bag-Components`
  - Source: `ContainerFrame.xml`

## Folder Coverage

| Interface folder | Static paths found |
| --- | ---: |
| `Buttons` | 114 |
| `ChatFrame` | 61 |
| `PaperDollInfoFrame` | 38 |
| `AchievementFrame` | 37 |
| `FriendsFrame` | 34 |
| `QuestFrame` | 26 |
| `MiniMap` | 22 |
| `TargetingFrame` | 19 |
| `LFGFrame` | 18 |
| `Vehicles` | 17 |
| `AuctionFrame` | 16 |
| `HelpFrame` | 15 |
| `SpellBook` | 15 |
| `Calendar` | 14 |
| `MainMenuBar` | 14 |
| `Common` | 13 |
| `MerchantFrame` | 11 |
| `ClassTrainerFrame` | 10 |
| `WorldMap` | 10 |
| `BattlefieldFrame` | 9 |
| `MoneyFrame` | 9 |
| `RaidFrame` | 9 |
| `WorldStateFrame` | 9 |
| `CharacterFrame` | 8 |
| `DialogFrame` | 8 |
| `GuildBankFrame` | 7 |
| `MacroFrame` | 7 |
| `PetPaperDollFrame` | 7 |
| `PVPFrame` | 7 |
| `KeyBindingFrame` | 6 |
| `MailFrame` | 6 |
| `OptionsFrame` | 6 |
| `TalentFrame` | 6 |
| `TradeFrame` | 6 |
| `CastingBar` | 5 |
| `Glues` | 5 |
| `TaxiFrame` | 5 |
| `Icons` | 4 |
| `PetStableFrame` | 4 |
| `TicTacToeFrame` | 4 |
| `TimeManager` | 4 |
| `ContainerFrame` | 3 |
| `ItemSocketingFrame` | 3 |
| `TabardFrame` | 3 |
| `Tooltips` | 3 |
| `TutorialFrame` | 3 |
| `ArenaEnemyFrame` | 2 |
| `GroupFrame` | 2 |
| `ItemTextFrame` | 2 |
| `PlayerFrame` | 2 |
| `ShapeshiftBar` | 2 |
| `TradeSkillFrame` | 2 |
| `BankFrame` | 1 |
| `ComboFrame` | 1 |
| `Durability` | 1 |
| `FullScreenTextures` | 1 |
| `GMChatFrame` | 1 |
| `GossipFrame` | 1 |
| `ItemAnimations` | 1 |
| `LootFrame` | 1 |
| `PetActionBar` | 1 |
| `PetitionFrame` | 1 |
| `PvPRankBadges` | 1 |
| `TokenFrame` | 1 |

## Full Static Path Index

### Interface\AchievementFrame

- `Interface\AchievementFrame\UI-Achievement-AchievementBackground`
- `Interface\AchievementFrame\UI-Achievement-AchievementWatermark`
- `Interface\AchievementFrame\UI-Achievement-Alert-Background`
- `Interface\AchievementFrame\UI-Achievement-Alert-Glow`
- `Interface\AchievementFrame\UI-Achievement-Bling`
- `Interface\AchievementFrame\UI-Achievement-Category-Background`
- `Interface\AchievementFrame\UI-Achievement-Category-Highlight`
- `Interface\AchievementFrame\UI-Achievement-ComparisonHeader`
- `Interface\AchievementFrame\UI-Achievement-Criteria-Check`
- `Interface\AchievementFrame\UI-Achievement-Header`
- `Interface\AchievementFrame\UI-Achievement-IconFrame`
- `Interface\AchievementFrame\UI-Achievement-IconFrame-Backfill`
- `Interface\AchievementFrame\UI-Achievement-MetalBorder-Joint`
- `Interface\AchievementFrame\UI-Achievement-MetalBorder-Left`
- `Interface\AchievementFrame\UI-Achievement-MetalBorder-Top`
- `Interface\AchievementFrame\UI-Achievement-Parchment`
- `Interface\AchievementFrame\UI-Achievement-Parchment-Highlight`
- `Interface\AchievementFrame\UI-Achievement-Parchment-Horizontal`
- `Interface\AchievementFrame\UI-Achievement-PlusMinus`
- `Interface\AchievementFrame\UI-Achievement-ProgressBar-Border`
- `Interface\AchievementFrame\UI-Achievement-Progressive-IconBorder`
- `Interface\AchievementFrame\UI-Achievement-Progressive-Shield`
- `Interface\AchievementFrame\UI-Achievement-RecentHeader`
- `Interface\AchievementFrame\UI-Achievement-Reward-Background`
- `Interface\AchievementFrame\UI-Achievement-RightDDLInset`
- `Interface\AchievementFrame\UI-Achievement-Shields`
- `Interface\AchievementFrame\UI-Achievement-Shields-NoPoints`
- `Interface\AchievementFrame\UI-Achievement-Stat-Buttons`
- `Interface\AchievementFrame\UI-Achievement-StatsBackground`
- `Interface\AchievementFrame\UI-Achievement-StatsComparisonBackground`
- `Interface\AchievementFrame\UI-Achievement-StatusBar-Highlight`
- `Interface\AchievementFrame\UI-Achievement-TinyShield`
- `Interface\AchievementFrame\UI-Achievement-Title`
- `Interface\AchievementFrame\UI-Achievement-Tsunami-Corners`
- `Interface\AchievementFrame\UI-Achievement-Tsunami-Horizontal`
- `Interface\AchievementFrame\UI-Achievement-WoodBorder`
- `Interface\AchievementFrame\UI-Achievement-WoodBorder-Corner`
### Interface\ArenaEnemyFrame

- `Interface\ArenaEnemyFrame\UI-Arena-Border`
- `Interface\ArenaEnemyFrame\UI-ArenaTargetingFrame`
### Interface\AuctionFrame

- `Interface\AuctionFrame\AuctionHouseDressUpFrame-Bottom`
- `Interface\AuctionFrame\AuctionHouseDressUpFrame-Corner`
- `Interface\AuctionFrame\AuctionHouseDressUpFrame-Top`
- `Interface\AuctionFrame\UI-AuctionFrame-Browse-Bot`
- `Interface\AuctionFrame\UI-AuctionFrame-Browse-BotLeft`
- `Interface\AuctionFrame\UI-AuctionFrame-Browse-BotRight`
- `Interface\AuctionFrame\UI-AuctionFrame-Browse-Top`
- `Interface\AuctionFrame\UI-AuctionFrame-Browse-TopLeft`
- `Interface\AuctionFrame\UI-AuctionFrame-Browse-TopRight`
- `Interface\AuctionFrame\UI-AuctionFrame-FilterBg`
- `Interface\AuctionFrame\UI-AuctionFrame-FilterLines`
- `Interface\AuctionFrame\UI-AuctionFrame-ItemSlot`
- `Interface\AuctionFrame\UI-AuctionItemNameFrame`
- `Interface\AuctionFrame\UI-AuctionPost-Background`
- `Interface\AuctionFrame\UI-AuctionPost-Endcaps`
- `Interface\AuctionFrame\UI-AuctionPost-Middle`
### Interface\BankFrame

- `Interface\BankFrame\UI-BankFrame`
### Interface\BattlefieldFrame

- `Interface\BattlefieldFrame\UI-Battlefield-Bar`
- `Interface\BattlefieldFrame\UI-Battlefield-BotLeft`
- `Interface\BattlefieldFrame\UI-Battlefield-BotRight`
- `Interface\BattlefieldFrame\UI-Battlefield-Icon`
- `Interface\BattlefieldFrame\UI-Battlefield-TopLeft`
- `Interface\BattlefieldFrame\UI-Battlefield-TopRight`
- `Interface\BattlefieldFrame\UI-BattlefieldMinimap-Border`
- `Interface\BattlefieldFrame\UI-QueueFromAnywhere-BotLeft`
- `Interface\BattlefieldFrame\UI-QueueFromAnywhere-BotRight`
### Interface\Buttons

- `Interface\Buttons\Arrow-Down-Disabled`
- `Interface\Buttons\Arrow-Down-Down`
- `Interface\Buttons\Arrow-Down-Up`
- `Interface\Buttons\Arrow-Up-Disabled`
- `Interface\Buttons\Arrow-Up-Down`
- `Interface\Buttons\Arrow-Up-Up`
- `Interface\Buttons\ButtonHilight-Round`
- `Interface\Buttons\ButtonHilight-Square`
- `Interface\BUTTONS\ButtonHilight-Square`
- `Interface\Buttons\CancelButton-Down`
- `Interface\Buttons\CancelButton-Highlight`
- `Interface\Buttons\CancelButton-Up`
- `Interface\Buttons\CheckButtonGlow`
- `Interface\Buttons\CheckButtonHilight`
- `Interface\Buttons\UI-ActionButton-Border`
- `Interface\Buttons\UI-AutoCastableOverlay`
- `Interface\Buttons\UI-Button-Borders`
- `Interface\Buttons\UI-Button-Borders2`
- `Interface\Buttons\UI-Button-KeyRing`
- `Interface\Buttons\UI-Button-KeyRing-Down`
- `Interface\Buttons\UI-Button-KeyRing-Highlight`
- `Interface\Buttons\UI-Button-Outline`
- `Interface\Buttons\UI-CheckBox-Check`
- `Interface\Buttons\UI-CheckBox-Check-Disabled`
- `Interface\Buttons\UI-CheckBox-Down`
- `Interface\Buttons\UI-CheckBox-Highlight`
- `Interface\Buttons\UI-CheckBox-SwordCheck`
- `Interface\Buttons\UI-CheckBox-Up`
- `Interface\Buttons\UI-ColorPicker-Buttons`
- `Interface\Buttons\UI-Common-MouseHilight`
- `Interface\Buttons\UI-Debuff-Overlays`
- `Interface\Buttons\UI-DialogBox-Button-Disabled`
- `Interface\Buttons\UI-DialogBox-Button-Down`
- `Interface\Buttons\UI-DialogBox-Button-Highlight`
- `Interface\Buttons\UI-DialogBox-Button-Up`
- `Interface\Buttons\UI-EmptySlot`
- `Interface\Buttons\UI-EmptySlot-Disabled`
- `Interface\Buttons\UI-EmptySlot-White`
- `Interface\Buttons\UI-GroupLoot-Coin-Down`
- `Interface\Buttons\UI-GroupLoot-Coin-Highlight`
- `Interface\Buttons\UI-GroupLoot-Coin-Up`
- `Interface\Buttons\UI-GroupLoot-DE-Down`
- `Interface\Buttons\UI-GroupLoot-DE-Highlight`
- `Interface\Buttons\UI-GroupLoot-DE-Up`
- `Interface\Buttons\UI-GroupLoot-Dice-Down`
- `Interface\Buttons\UI-GroupLoot-Dice-Highlight`
- `Interface\Buttons\UI-GroupLoot-Dice-Up`
- `Interface\Buttons\UI-ListBox-Highlight`
- `Interface\Buttons\UI-Listbox-Highlight2`
- `Interface\Buttons\UI-MicroButton-Hilight`
- `Interface\Buttons\UI-MinusButton-Disabled`
- `Interface\Buttons\UI-MinusButton-Down`
- `Interface\Buttons\UI-MinusButton-DOWN`
- `Interface\Buttons\UI-MinusButton-UP`
- `Interface\Buttons\UI-MinusButton-Up`
- `Interface\Buttons\UI-PageButton-Background`
- `Interface\Buttons\UI-Panel-BiggerButton-Down`
- `Interface\Buttons\UI-Panel-BiggerButton-Up`
- `Interface\Buttons\UI-Panel-Button-Disabled`
- `Interface\Buttons\UI-Panel-Button-Disabled-Down`
- `Interface\Buttons\UI-Panel-Button-Down`
- `Interface\Buttons\UI-Panel-Button-Glow`
- `Interface\Buttons\UI-Panel-Button-Highlight`
- `Interface\Buttons\UI-Panel-Button-Up`
- `Interface\Buttons\UI-Panel-HideButton-Down`
- `Interface\Buttons\UI-Panel-HideButton-Up`
- `Interface\BUTTONS\UI-Panel-MinimizeButton-Disabled`
- `Interface\BUTTONS\UI-Panel-MinimizeButton-Down`
- `Interface\Buttons\UI-Panel-MinimizeButton-Down`
- `Interface\BUTTONS\UI-Panel-MinimizeButton-Highlight`
- `Interface\Buttons\UI-Panel-MinimizeButton-Highlight`
- `Interface\BUTTONS\UI-Panel-MinimizeButton-Up`
- `Interface\Buttons\UI-Panel-MinimizeButton-Up`
- `Interface\Buttons\UI-Panel-QuestHideButton`
- `Interface\Buttons\UI-Panel-QuestHideButton-disabled`
- `Interface\Buttons\UI-Panel-SmallerButton-Down`
- `Interface\Buttons\UI-Panel-SmallerButton-Up`
- `Interface\Buttons\UI-PlusButton-Disabled`
- `Interface\Buttons\UI-PlusButton-Down`
- `Interface\Buttons\UI-PlusButton-Hilight`
- `Interface\Buttons\UI-PlusButton-Up`
- `Interface\Buttons\UI-PlusMinus-Buttons`
- `Interface\Buttons\UI-Quickslot-Depress`
- `Interface\Buttons\UI-Quickslot2`
- `Interface\Buttons\UI-QuickslotRed`
- `Interface\Buttons\UI-RadioButton`
- `Interface\Buttons\UI-RotationLeft-Button-Down`
- `Interface\Buttons\UI-RotationLeft-Button-Up`
- `Interface\Buttons\UI-RotationRight-Button-Down`
- `Interface\Buttons\UI-RotationRight-Button-Up`
- `Interface\Buttons\UI-ScrollBar-Button-Overlay`
- `Interface\Buttons\UI-ScrollBar-Knob`
- `Interface\Buttons\UI-ScrollBar-ScrollDownButton-Disabled`
- `Interface\Buttons\UI-ScrollBar-ScrollDownButton-Down`
- `Interface\Buttons\UI-ScrollBar-ScrollDownButton-Highlight`
- `Interface\Buttons\UI-ScrollBar-ScrollDownButton-Up`
- `Interface\Buttons\UI-ScrollBar-ScrollUpButton-Disabled`
- `Interface\Buttons\UI-ScrollBar-ScrollUpButton-Down`
- `Interface\Buttons\UI-ScrollBar-ScrollUpButton-Highlight`
- `Interface\Buttons\UI-ScrollBar-ScrollUpButton-Up`
- `Interface\Buttons\UI-SliderBar-Background`
- `Interface\Buttons\UI-SliderBar-Border`
- `Interface\Buttons\UI-SliderBar-Button-Horizontal`
- `Interface\Buttons\UI-SliderBar-Button-Vertical`
- `Interface\Buttons\UI-Slot-Background`
- `Interface\Buttons\UI-SortArrow`
- `Interface\Buttons\UI-SpellbookIcon-NextPage-Disabled`
- `Interface\Buttons\UI-SpellbookIcon-NextPage-Down`
- `Interface\Buttons\UI-SpellbookIcon-NextPage-Up`
- `Interface\Buttons\UI-SpellbookIcon-PrevPage-Disabled`
- `Interface\Buttons\UI-SpellbookIcon-PrevPage-Down`
- `Interface\Buttons\UI-SpellbookIcon-PrevPage-Up`
- `Interface\Buttons\UI-TempEnchant-Border`
- `Interface\Buttons\UI-TotemBar`
### Interface\Calendar

- `Interface\Calendar\CalendarBackground`
- `Interface\Calendar\CalendarEventBackground`
- `Interface\Calendar\CalendarFrame_Sides`
- `Interface\Calendar\CalendarFrame_TopAndBottom`
- `Interface\Calendar\CalendarShadows`
- `Interface\Calendar\CurrentDay`
- `Interface\Calendar\DateBackgrounds`
- `Interface\Calendar\EventHighlight`
- `Interface\Calendar\EventNotification`
- `Interface\Calendar\EventNotificationGlow`
- `Interface\Calendar\Highlights`
- `Interface\Calendar\MoreArrow`
- `Interface\Calendar\UI-Calendar-Button`
- `Interface\Calendar\UI-Calendar-Button-Glow`
### Interface\CastingBar

- `Interface\CastingBar\UI-CastingBar-Arena-Shield`
- `Interface\CastingBar\UI-CastingBar-Border`
- `Interface\CastingBar\UI-CastingBar-Flash`
- `Interface\CastingBar\UI-CastingBar-Small-Shield`
- `Interface\CastingBar\UI-CastingBar-Spark`
### Interface\CharacterFrame

- `Interface\CharacterFrame\Disconnect-Icon`
- `Interface\CharacterFrame\TotemBorder`
- `Interface\CharacterFrame\UI-CharacterFrame-GroupIndicator`
- `Interface\CharacterFrame\UI-Party-Background`
- `Interface\CharacterFrame\UI-Party-Border`
- `Interface\CharacterFrame\UI-Player-PlayTimeTired`
- `Interface\CharacterFrame\UI-Player-Status`
- `Interface\CharacterFrame\UI-StateIcon`
### Interface\ChatFrame

- `Interface\ChatFrame\chat-tab-arrow`
- `Interface\ChatFrame\chat-tab-arrow-on`
- `Interface\ChatFrame\ChatFrameBackground`
- `Interface\ChatFrame\ChatFrameColorSwatch`
- `Interface\ChatFrame\ChatFrameExpandArrow`
- `Interface\ChatFrame\ChatFrameTab`
- `Interface\ChatFrame\ChatFrameTab-BGLeft`
- `Interface\ChatFrame\ChatFrameTab-BGLeft-min`
- `Interface\ChatFrame\ChatFrameTab-BGMid`
- `Interface\ChatFrame\ChatFrameTab-BGMid-min`
- `Interface\ChatFrame\ChatFrameTab-BGRight`
- `Interface\ChatFrame\ChatFrameTab-BGRight-min`
- `Interface\ChatFrame\ChatFrameTab-HighlightLeft`
- `Interface\ChatFrame\ChatFrameTab-HighlightLeft-min`
- `Interface\ChatFrame\ChatFrameTab-HighlightMid`
- `Interface\ChatFrame\ChatFrameTab-HighlightMid-min`
- `Interface\ChatFrame\ChatFrameTab-HighlightRight`
- `Interface\ChatFrame\ChatFrameTab-HighlightRight-min`
- `Interface\ChatFrame\ChatFrameTab-NewMessage`
- `Interface\ChatFrame\ChatFrameTab-SelectedLeft`
- `Interface\ChatFrame\ChatFrameTab-SelectedMid`
- `Interface\ChatFrame\ChatFrameTab-SelectedRight`
- `Interface\ChatFrame\UI-ChatConversationIcon`
- `Interface\ChatFrame\UI-ChatFrame-BorderCorner`
- `Interface\ChatFrame\UI-ChatFrame-BorderLeft`
- `Interface\ChatFrame\UI-ChatFrame-BorderTop`
- `Interface\ChatFrame\UI-ChatFrame-DockHighlight`
- `Interface\ChatFrame\UI-ChatIcon-BattleBro-Down`
- `Interface\ChatFrame\UI-ChatIcon-BattleBro-Up`
- `Interface\ChatFrame\UI-ChatIcon-BlinkHilight`
- `Interface\ChatFrame\UI-ChatIcon-Blizz`
- `Interface\ChatFrame\UI-ChatIcon-Chat-Disabled`
- `Interface\ChatFrame\UI-ChatIcon-Chat-Down`
- `Interface\ChatFrame\UI-ChatIcon-Chat-Up`
- `Interface\ChatFrame\UI-ChatIcon-Maximize-Down`
- `Interface\ChatFrame\UI-ChatIcon-Maximize-Up`
- `Interface\ChatFrame\UI-ChatIcon-Minimize-Down`
- `Interface\ChatFrame\UI-ChatIcon-Minimize-Up`
- `Interface\ChatFrame\UI-ChatIcon-ScrollDown-Disabled`
- `Interface\ChatFrame\UI-ChatIcon-ScrollDown-Down`
- `Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up`
- `Interface\ChatFrame\UI-ChatIcon-ScrollEnd-Disabled`
- `Interface\ChatFrame\UI-ChatIcon-ScrollEnd-Down`
- `Interface\ChatFrame\UI-ChatIcon-ScrollEnd-Up`
- `Interface\ChatFrame\UI-ChatIcon-ScrollUp-Disabled`
- `Interface\ChatFrame\UI-ChatIcon-ScrollUp-Down`
- `Interface\ChatFrame\UI-ChatIcon-ScrollUp-Up`
- `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down`
- `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight`
- `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up`
- `Interface\ChatFrame\UI-ChatInputBorder-Left`
- `Interface\ChatFrame\UI-ChatInputBorder-Left2`
- `Interface\ChatFrame\UI-ChatInputBorder-Mid2`
- `Interface\ChatFrame\UI-ChatInputBorder-Right`
- `Interface\ChatFrame\UI-ChatInputBorder-Right2`
- `Interface\ChatFrame\UI-ChatInputBorderFocus-Left`
- `Interface\ChatFrame\UI-ChatInputBorderFocus-Mid`
- `Interface\ChatFrame\UI-ChatInputBorderFocus-Right`
- `Interface\ChatFrame\UI-ChatRosterIcon-Disabled`
- `Interface\ChatFrame\UI-ChatRosterIcon-Down`
- `Interface\ChatFrame\UI-ChatRosterIcon-Up`
### Interface\ClassTrainerFrame

- `Interface\ClassTrainerFrame\UI-ClassTrainer-BotLeft`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-BotRight`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-DetailHeaderLeft`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-DetailHeaderRight`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-ExpandTab-Left`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-FilterBorder`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-HorizontalBar`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-ScrollBar`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-TopLeft`
- `Interface\ClassTrainerFrame\UI-ClassTrainer-TopRight`
### Interface\ComboFrame

- `Interface\ComboFrame\ComboPoint`
### Interface\Common

- `Interface\Common\Common-Input-Border`
- `Interface\Common\Common-Input-Border-B`
- `Interface\Common\Common-Input-Border-BL`
- `Interface\Common\Common-Input-Border-BR`
- `Interface\Common\Common-Input-Border-L`
- `Interface\Common\Common-Input-Border-M`
- `Interface\Common\Common-Input-Border-R`
- `Interface\Common\Common-Input-Border-T`
- `Interface\Common\Common-Input-Border-TL`
- `Interface\Common\Common-Input-Border-TR`
- `Interface\Common\VoiceChat-Muted`
- `Interface\Common\VoiceChat-On`
- `Interface\Common\VoiceChat-Speaker`
### Interface\ContainerFrame

- `Interface\ContainerFrame\UI-Backpack-TokenFrame`
- `Interface\ContainerFrame\UI-Bag-1Slot`
- `Interface\ContainerFrame\UI-Bag-Components`
### Interface\DialogFrame

- `Interface\DialogFrame\UI-Dialog-Icon-AlertNew`
- `Interface\DialogFrame\UI-DialogBox-Background`
- `Interface\DialogFrame\UI-DialogBox-Background-Dark`
- `Interface\DialogFrame\UI-DialogBox-Border`
- `Interface\DialogFrame\UI-DialogBox-Corner`
- `Interface\DialogFrame\UI-DialogBox-Divider`
- `Interface\DialogFrame\UI-DialogBox-Gold-Dragon`
- `Interface\DialogFrame\UI-DialogBox-Header`
### Interface\Durability

- `Interface\Durability\UI-Durability-Icons`
### Interface\FriendsFrame

- `Interface\FriendsFrame\Battlenet-WoWicon`
- `Interface\FriendsFrame\BlockCommunicationsIcon`
- `Interface\FriendsFrame\BroadcastIcon`
- `Interface\FriendsFrame\ClearBroadcastIcon`
- `Interface\FriendsFrame\FriendsFrameScrollIcon`
- `Interface\FriendsFrame\InformationIcon`
- `Interface\FriendsFrame\InformationIcon-Highlight`
- `Interface\FriendsFrame\PendingFriendNameBG`
- `Interface\FriendsFrame\PendingFriendNameBG-New`
- `Interface\FriendsFrame\PlusManz-BattleNet`
- `Interface\FriendsFrame\PlusManz-BattleNetBG`
- `Interface\FriendsFrame\PlusManz-Horde`
- `Interface\FriendsFrame\PlusManz-PlusManz`
- `Interface\FriendsFrame\ReportSpamIcon`
- `Interface\FriendsFrame\StatusIcon-Online`
- `Interface\FriendsFrame\UI-ChannelFrame-Titlebar`
- `Interface\FriendsFrame\UI-ChannelFrame-VerticalBar`
- `Interface\FriendsFrame\UI-FriendsFrame-BotLeft-bnet`
- `Interface\FriendsFrame\UI-FriendsFrame-BotRight-bnet`
- `Interface\FriendsFrame\UI-FriendsFrame-HighlightBar`
- `Interface\FriendsFrame\UI-FriendsFrame-Link`
- `Interface\FriendsFrame\UI-FriendsFrame-Note`
- `Interface\FriendsFrame\UI-FriendsFrame-OnlineDivider`
- `Interface\FriendsFrame\UI-FriendsFrame-TopLeft-bnet`
- `Interface\FriendsFrame\UI-FriendsFrame-TopRight-bnet`
- `Interface\FriendsFrame\UI-GuildMember-Patch`
- `Interface\FriendsFrame\UI-Toast-Background`
- `Interface\FriendsFrame\UI-Toast-Border`
- `Interface\FriendsFrame\UI-Toast-CloseButton-Down`
- `Interface\FriendsFrame\UI-Toast-CloseButton-Highlight`
- `Interface\FriendsFrame\UI-Toast-CloseButton-Up`
- `Interface\FriendsFrame\UI-Toast-Flair`
- `Interface\FriendsFrame\UI-Toast-ToastIcons`
- `Interface\FriendsFrame\WhoFrame-ColumnTabs`
### Interface\FullScreenTextures

- `Interface\FullScreenTextures\LowHealth`
### Interface\Glues

- `Interface\Glues\CharacterCreate\CharacterCreate-LabelFrame`
- `Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes`
- `Interface\Glues\Login\Glues-KoreanRating-Age`
- `Interface\Glues\Login\Glues-KoreanRating-Drugs`
- `Interface\Glues\Login\Glues-KoreanRating-Violence`
### Interface\GMChatFrame

- `Interface\GMChatFrame\UI-GMStatusFrame-Pulse`
### Interface\GossipFrame

- `Interface\GossipFrame\AvailableQuestIcon`
### Interface\GroupFrame

- `Interface\GroupFrame\UI-Group-LeaderIcon`
- `Interface\GroupFrame\UI-Group-MasterLooter`
### Interface\GuildBankFrame

- `Interface\GuildBankFrame\UI-GuildBankFrame-EmblemBorder`
- `Interface\GuildBankFrame\UI-GuildBankFrame-Left`
- `Interface\GuildBankFrame\UI-GuildBankFrame-Right`
- `Interface\GuildBankFrame\UI-GuildBankFrame-Slots`
- `Interface\GuildBankFrame\UI-GuildBankFrame-Tab`
- `Interface\GuildBankFrame\UI-GuildFrame-PermissionTab`
- `Interface\GuildBankFrame\UI-TabNameBorder`
### Interface\HelpFrame

- `Interface\HelpFrame\HelpFrame-BotLeft`
- `Interface\HelpFrame\HelpFrame-BotLeftBig`
- `Interface\HelpFrame\HelpFrame-BotRight`
- `Interface\HelpFrame\HelpFrame-BotRightBig`
- `Interface\HelpFrame\HelpFrame-Bottom`
- `Interface\HelpFrame\HelpFrame-BottomBig`
- `Interface\HelpFrame\HelpFrame-Top`
- `Interface\HelpFrame\HelpFrame-TopLeft`
- `Interface\HelpFrame\HelpFrame-TopRight`
- `Interface\HelpFrame\HelpFrameButton-Highlight`
- `Interface\HelpFrame\HelpFrameDivider`
- `Interface\HelpFrame\HelpFrameTab-Active`
- `Interface\HelpFrame\HelpFrameTab-Inactive`
- `Interface\HelpFrame\HotIssueIcon`
- `Interface\HelpFrame\OpenTicketIcon`
### Interface\Icons

- `Interface\Icons\INV_Letter_15`
- `Interface\Icons\INV_Misc_Note_02`
- `Interface\Icons\INV_Misc_PocketWatch_01`
- `Interface\Icons\Spell_Misc_HellifrePVPHonorHoldFavor`
### Interface\ItemAnimations

- `Interface\ItemAnimations\ForcedBackpackItem`
### Interface\ItemSocketingFrame

- `Interface\ItemSocketingFrame\UI-ItemSocketingFrame`
- `Interface\ItemSocketingFrame\UI-ItemSocketingFrame-ScrollBar`
- `Interface\ItemSocketingFrame\UI-ItemSockets`
### Interface\ItemTextFrame

- `Interface\ItemTextFrame\UI-ItemText-BotLeft`
- `Interface\ItemTextFrame\UI-ItemText-TopLeft`
### Interface\KeyBindingFrame

- `Interface\KeyBindingFrame\UI-KeyBindingFrame-Bot`
- `Interface\KeyBindingFrame\UI-KeyBindingFrame-BotLeft`
- `Interface\KeyBindingFrame\UI-KeyBindingFrame-BotRight`
- `Interface\KeyBindingFrame\UI-KeyBindingFrame-Top`
- `Interface\KeyBindingFrame\UI-KeyBindingFrame-TopLeft`
- `Interface\KeyBindingFrame\UI-KeyBindingFrame-TopRight`
### Interface\LFGFrame

- `Interface\LFGFrame\LFG-Eye`
- `Interface\LFGFrame\LFGRole`
- `Interface\LFGFrame\UI-LFG-BACKGROUND-QUESTPAPER`
- `Interface\LFGFrame\UI-LFG-BACKGROUND-RANDOMDUNGEON`
- `Interface\LFGFrame\UI-LFG-DUNGEONTOAST`
- `Interface\LFGFrame\UI-LFG-FILIGREE`
- `Interface\LFGFrame\UI-LFG-FRAME`
- `Interface\LFGFrame\UI-LFG-ICON-HEROIC`
- `Interface\LFGFrame\UI-LFG-ICON-LOCK`
- `Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES`
- `Interface\LFGFrame\UI-LFG-ICON-REWARDRING`
- `Interface\LFGFrame\UI-LFG-ICON-ROLES`
- `Interface\LFGFrame\UI-LFG-ICONS-ROLEBACKGROUNDS`
- `Interface\LFGFrame\UI-LFG-PORTRAIT`
- `Interface\LFGFrame\UI-LFG-SEPARATOR`
- `Interface\LFGFrame\UI-LFR-FRAME-BROWSE`
- `Interface\LFGFrame\UI-LFR-FRAME-MAIN`
- `Interface\LFGFrame\UI-LFR-PORTRAIT`
### Interface\LootFrame

- `Interface\LootFrame\UI-LootPanel`
### Interface\MacroFrame

- `Interface\MacroFrame\MacroFrame-BotLeft`
- `Interface\MacroFrame\MacroFrame-BotRight`
- `Interface\MacroFrame\MacroFrame-Icon`
- `Interface\MacroFrame\MacroPopup-BotLeft`
- `Interface\MacroFrame\MacroPopup-BotRight`
- `Interface\MacroFrame\MacroPopup-TopLeft`
- `Interface\MacroFrame\MacroPopup-TopRight`
### Interface\MailFrame

- `Interface\MailFrame\Mail-Icon`
- `Interface\MailFrame\MailItemBorder`
- `Interface\MailFrame\MailPopup-Bottom`
- `Interface\MailFrame\MailPopup-Top`
- `Interface\MailFrame\UI-MailFrame-InvoiceLine`
- `Interface\MailFrame\UI-OpenMail-BotLeft`
### Interface\MainMenuBar

- `Interface\MainMenuBar\UI-ExhaustionTickHighlight`
- `Interface\MainMenuBar\UI-ExhaustionTickNormal`
- `Interface\MainMenuBar\UI-MainMenu-ScrollDownButton-Disabled`
- `Interface\MainMenuBar\UI-MainMenu-ScrollDownButton-Down`
- `Interface\MainMenuBar\UI-MainMenu-ScrollDownButton-Highlight`
- `Interface\MainMenuBar\UI-MainMenu-ScrollDownButton-Up`
- `Interface\MainMenuBar\UI-MainMenu-ScrollUpButton-Disabled`
- `Interface\MainMenuBar\UI-MainMenu-ScrollUpButton-Down`
- `Interface\MainMenuBar\UI-MainMenu-ScrollUpButton-Highlight`
- `Interface\MainMenuBar\UI-MainMenu-ScrollUpButton-Up`
- `Interface\MainMenuBar\UI-MainMenuBar-Dwarf`
- `Interface\MainMenuBar\UI-MainMenuBar-EndCap-Dwarf`
- `Interface\MainMenuBar\UI-MainMenuBar-MaxLevel`
- `Interface\MainMenuBar\UI-MainMenuBar-PerformanceBar`
### Interface\MerchantFrame

- `Interface\MerchantFrame\UI-BuyBack-BotLeft`
- `Interface\MerchantFrame\UI-BuyBack-BotRight`
- `Interface\MerchantFrame\UI-BuyBack-TopLeft`
- `Interface\MerchantFrame\UI-BuyBack-TopRight`
- `Interface\MerchantFrame\UI-Merchant-BotLeft`
- `Interface\MerchantFrame\UI-Merchant-BotRight`
- `Interface\MerchantFrame\UI-Merchant-BottomBorder`
- `Interface\MerchantFrame\UI-Merchant-LabelSlots`
- `Interface\MerchantFrame\UI-Merchant-RepairIcons`
- `Interface\MerchantFrame\UI-Merchant-TopLeft`
- `Interface\MerchantFrame\UI-Merchant-TopRight`
### Interface\MiniMap

- `Interface\Minimap\CompassNorthTag`
- `Interface\Minimap\CompassRing`
- `Interface\Minimap\MiniMap-TrackingBorder`
- `Interface\Minimap\MinimapArrow`
- `Interface\Minimap\MovieRecordingIcon`
- `Interface\MiniMap\Ping\MinimapPing`
- `Interface\Minimap\POIIcons`
- `Interface\Minimap\Rotating-MinimapArrow`
- `Interface\Minimap\UI-DungeonDifficulty-Button`
- `Interface\Minimap\UI-Minimap-Background`
- `Interface\Minimap\UI-Minimap-Border`
- `Interface\Minimap\UI-Minimap-Ping-Center`
- `Interface\Minimap\UI-Minimap-Ping-Expand`
- `Interface\Minimap\UI-Minimap-Ping-Rotate`
- `Interface\Minimap\UI-Minimap-ZoomButton-Highlight`
- `Interface\Minimap\UI-Minimap-ZoomInButton-Disabled`
- `Interface\Minimap\UI-Minimap-ZoomInButton-Down`
- `Interface\Minimap\UI-Minimap-ZoomInButton-Up`
- `Interface\Minimap\UI-Minimap-ZoomOutButton-Disabled`
- `Interface\Minimap\UI-Minimap-ZoomOutButton-Down`
- `Interface\Minimap\UI-Minimap-ZoomOutButton-Up`
- `Interface\Minimap\UI-TOD-Indicator`
### Interface\MoneyFrame

- `Interface\MoneyFrame\Arrow-Left-Disabled`
- `Interface\MoneyFrame\Arrow-Left-Down`
- `Interface\MoneyFrame\Arrow-Left-Up`
- `Interface\MoneyFrame\Arrow-Right-Disabled`
- `Interface\MoneyFrame\Arrow-Right-Down`
- `Interface\MoneyFrame\Arrow-Right-Up`
- `Interface\MoneyFrame\UI-MoneyFrame`
- `Interface\MoneyFrame\UI-MoneyFrame-Border`
- `Interface\MoneyFrame\UI-MoneyIcons`
### Interface\OptionsFrame

- `Interface\OptionsFrame\21stepgrayscale`
- `Interface\OptionsFrame\UI-OptionsFrame-ActiveTab`
- `Interface\OptionsFrame\UI-OptionsFrame-InActiveTab`
- `Interface\OptionsFrame\UI-OptionsFrame-Spacer`
- `Interface\OptionsFrame\VoiceChat-Play`
- `Interface\OptionsFrame\VoiceChat-Record`
### Interface\PaperDollInfoFrame

- `Interface\PaperDollInfoFrame\SkillFrame-BotLeft`
- `Interface\PaperDollInfoFrame\SkillFrame-BotRight`
- `Interface\PaperDollInfoFrame\UI-Character-ActiveTab`
- `Interface\PaperdollInfoFrame\UI-Character-AmmoSlot`
- `Interface\PaperDollInfoFrame\UI-Character-CharacterTab-BottomLeft`
- `Interface\PaperDollInfoFrame\UI-Character-CharacterTab-BottomRight`
- `Interface\PaperDollInfoFrame\UI-Character-CharacterTab-L1`
- `Interface\PaperDollInfoFrame\UI-Character-CharacterTab-R1`
- `Interface\PaperDollInfoFrame\UI-Character-General-BottomLeft`
- `Interface\PaperDollInfoFrame\UI-Character-General-BottomRight`
- `Interface\PaperDollInfoFrame\UI-Character-General-TopLeft`
- `Interface\PaperDollInfoFrame\UI-Character-General-TopRight`
- `Interface\PaperDollInfoFrame\UI-Character-Honor-BottomLeft`
- `Interface\PaperDollInfoFrame\UI-Character-Honor-BottomRight`
- `Interface\PaperDollInfoFrame\UI-Character-Honor-TopLeft`
- `Interface\PaperDollInfoFrame\UI-Character-Honor-TopRight`
- `Interface\PaperDollInfoFrame\UI-Character-InActiveTab`
- `Interface\PaperDollInfoFrame\UI-Character-Reputation-DetailBackground`
- `Interface\PaperDollInfoFrame\UI-Character-ReputationBar`
- `Interface\PaperDollInfoFrame\UI-Character-ReputationBar-Highlight`
- `Interface\PaperDollInfoFrame\UI-Character-ReputationLines`
- `Interface\PaperDollInfoFrame\UI-Character-ResistanceIcons`
- `Interface\PaperDollInfoFrame\UI-Character-ScrollBar`
- `Interface\PaperDollInfoFrame\UI-Character-Skills-Bar`
- `Interface\PaperDollInfoFrame\UI-Character-Skills-BarBorder`
- `Interface\PaperDollInfoFrame\UI-Character-Skills-BarBorderHighlight`
- `Interface\PaperDollInfoFrame\UI-Character-StatBackground`
- `Interface\PaperDollInfoFrame\UI-Character-Tab-Highlight`
- `Interface\PaperDollInfoFrame\UI-Character-Tab-Highlight-yellow`
- `Interface\PaperDollInfoFrame\UI-GearManager-Border`
- `Interface\PaperDollInfoFrame\UI-GearManager-Button`
- `Interface\PaperDollInfoFrame\UI-GearManager-Button-Pushed`
- `Interface\PaperDollInfoFrame\UI-GearManager-Flyout`
- `Interface\PaperDollInfoFrame\UI-GearManager-FlyoutButton`
- `Interface\PaperDollInfoFrame\UI-GearManager-ItemButton-Highlight`
- `Interface\PaperDollInfoFrame\UI-GearManager-LeaveItem-Transparent`
- `Interface\PaperDollInfoFrame\UI-GearManager-Title-Background`
- `Interface\PaperDollInfoFrame\UI-ReputationWatchBar`
### Interface\PetActionBar

- `Interface\PetActionBar\UI-PetBar`
### Interface\PetitionFrame

- `Interface\PetitionFrame\GuildCharter-Icon`
### Interface\PetPaperDollFrame

- `Interface\PetPaperDollFrame\UI-PetFrame-Frame`
- `Interface\PetPaperDollFrame\UI-PetFrame-Slots`
- `Interface\PetPaperDollFrame\UI-PetFrame-Slots-Companions`
- `Interface\PetPaperDollFrame\UI-PetFrame-Slots-Mounts`
- `Interface\PetPaperDollFrame\UI-PetHappiness`
- `Interface\PetPaperDollFrame\UI-PetPaperDollFrame-BotLeft`
- `Interface\PetPaperDollFrame\UI-PetPaperDollFrame-BotRight`
### Interface\PetStableFrame

- `Interface\PetStableFrame\UI-PetStable-BottomLeft`
- `Interface\PetStableFrame\UI-PetStable-BottomRight`
- `Interface\PetStableFrame\UI-PetStable-TopLeft`
- `Interface\PetStableFrame\UI-PetStable-TopRight`
### Interface\PlayerFrame

- `Interface\PlayerFrame\UI-PlayerFrame-Deathknight-Blood`
- `Interface\PlayerFrame\UI-PlayerFrame-Deathknight-Ring`
### Interface\PVPFrame

- `Interface\PVPFrame\Icons\PVP-WintergraspTimerIcon`
- `Interface\PVPFrame\PVP-ArenaPoints-Icon`
- `Interface\PVPFrame\PVP-Currency-Horde`
- `Interface\PVPFrame\PvpRandomBg`
- `Interface\PVPFrame\UI-Character-PVP`
- `Interface\PVPFrame\UI-Character-PVP-Elements`
- `Interface\PVPFrame\UI-Character-PVP-Highlight`
### Interface\PvPRankBadges

- `Interface\PvPRankBadges\PvPRank06`
### Interface\QuestFrame

- `Interface\QuestFrame\UI-HorizontalBreak`
- `Interface\QuestFrame\UI-Quest-BotLeftPatch`
- `Interface\QuestFrame\UI-Quest-BulletPoint`
- `Interface\QuestFrame\UI-QuestDetails-BotLeft`
- `Interface\QuestFrame\UI-QuestDetails-BotRight`
- `Interface\QuestFrame\UI-QuestDetails-TopLeft`
- `Interface\QuestFrame\UI-QuestDetails-TopRight`
- `Interface\QuestFrame\UI-QuestGreeting-BotLeft`
- `Interface\QuestFrame\UI-QuestGreeting-BotRight`
- `Interface\QuestFrame\UI-QuestGreeting-TopLeft`
- `Interface\QuestFrame\UI-QuestGreeting-TopRight`
- `Interface\QuestFrame\UI-QuestItemHighlight`
- `Interface\QuestFrame\UI-QuestItemNameFrame`
- `Interface\QuestFrame\UI-QuestLog-BookIcon`
- `Interface\QuestFrame\UI-QuestLog-Empty-BotLeft`
- `Interface\QuestFrame\UI-QuestLog-Empty-BotRight`
- `Interface\QuestFrame\UI-QuestLog-Empty-TopLeft`
- `Interface\QuestFrame\UI-QuestLog-Empty-TopRight`
- `Interface\QuestFrame\UI-QuestLogDualPane-Left`
- `Interface\QuestFrame\UI-QuestLogDualPane-RIGHT`
- `Interface\QuestFrame\UI-QuestLogSortTab-Left`
- `Interface\QuestFrame\UI-QuestLogSortTab-Middle`
- `Interface\QuestFrame\UI-QuestLogSortTab-Right`
- `Interface\QuestFrame\UI-QuestLogTitleHighlight`
- `Interface\QuestFrame\UI-QuestMap_Button`
- `Interface\QuestFrame\UI-QuestTitleHighlight`
### Interface\RaidFrame

- `Interface\RaidFrame\ReadyCheck-Ready`
- `Interface\RaidFrame\ReadyCheck-Waiting`
- `Interface\RaidFrame\UI-RaidFrame-Arrow`
- `Interface\RaidFrame\UI-RaidFrame-GroupButton`
- `Interface\RaidFrame\UI-RaidFrame-GroupOutline`
- `Interface\RaidFrame\UI-RaidFrame-HealthBar`
- `Interface\RaidFrame\UI-RaidFrame-Threat`
- `Interface\RaidFrame\UI-RaidInfo-Header`
- `Interface\RaidFrame\UI-ReadyCheckFrame`
### Interface\ShapeshiftBar

- `Interface\ShapeshiftBar\ShapeshiftBar`
- `Interface\ShapeshiftBar\ShapeshiftBarMiddle`
### Interface\SpellBook

- `Interface\Spellbook\Spellbook-Icon`
- `Interface\SpellBook\SpellBook-SkillLineTab`
- `Interface\SpellBook\SpellBook-SkillLineTab-Glow`
- `Interface\Spellbook\UI-Glyph-Rune1`
- `Interface\Spellbook\UI-GlyphFrame`
- `Interface\Spellbook\UI-GlyphFrame-Glow`
- `Interface\Spellbook\UI-Spellbook-SpellBackground`
- `Interface\SpellBook\UI-SpellBook-Tab-Unselected`
- `Interface\SpellBook\UI-SpellBook-Tab1-Selected`
- `Interface\SpellBook\UI-SpellBook-Tab3-Selected`
- `Interface\Spellbook\UI-SpellbookPanel-BotLeft`
- `Interface\Spellbook\UI-SpellbookPanel-BotRight`
- `Interface\SpellBook\UI-SpellbookPanel-Tab-Highlight`
- `Interface\Spellbook\UI-SpellbookPanel-TopLeft`
- `Interface\Spellbook\UI-SpellbookPanel-TopRight`
### Interface\TabardFrame

- `Interface\TabardFrame\TabardFrameBackground`
- `Interface\TabardFrame\TabardFrameCustomizationFrame`
- `Interface\TabardFrame\TabardFrameOuterFrame`
### Interface\TalentFrame

- `Interface\TalentFrame\TalentFrame-RankBorder`
- `Interface\TalentFrame\UI-TalentArrows`
- `Interface\TalentFrame\UI-TalentBranches`
- `Interface\TalentFrame\UI-TalentFrame-BotLeft`
- `Interface\TalentFrame\UI-TalentFrame-BotRight`
- `Interface\TalentFrame\UI-TalentFrame-DualTalentSpec`
### Interface\TargetingFrame

- `Interface\TargetingFrame\NumericThreatBorder`
- `Interface\TargetingFrame\TargetDead`
- `Interface\TargetingFrame\UI-Classes-Circles`
- `Interface\TargetingFrame\UI-FocusFrame-Large`
- `Interface\TargetingFrame\UI-FocusTargetingFrame`
- `Interface\TargetingFrame\UI-PartyFrame`
- `Interface\TargetingFrame\UI-PartyFrame-Flash`
- `Interface\TargetingFrame\UI-Player-AttackStatus`
- `Interface\TargetingFrame\UI-RaidTargetingIcons`
- `Interface\TargetingFrame\UI-SmallTargetingFrame`
- `Interface\TargetingFrame\UI-StatusBar`
- `Interface\TargetingFrame\UI-TargetingFrame`
- `Interface\TargetingFrame\UI-TargetingFrame-AttackBackground`
- `Interface\TargetingFrame\UI-TargetingFrame-BarFill`
- `Interface\TargetingFrame\UI-TargetingFrame-Flash`
- `Interface\TargetingFrame\UI-TargetingFrame-LevelBackground`
- `Interface\TargetingFrame\UI-TargetingFrame-Skull`
- `Interface\TargetingFrame\UI-TargetingFrame-Stealable`
- `Interface\TargetingFrame\UI-TargetofTargetFrame`
### Interface\TaxiFrame

- `Interface\TaxiFrame\UI-Taxi-Icon-Highlight`
- `Interface\TaxiFrame\UI-TaxiFrame-BotLeft`
- `Interface\TaxiFrame\UI-TaxiFrame-BotRight`
- `Interface\TaxiFrame\UI-TaxiFrame-TopLeft`
- `Interface\TaxiFrame\UI-TaxiFrame-TopRight`
### Interface\TicTacToeFrame

- `Interface\TicTacToeFrame\TicTacToe-BottomLeft`
- `Interface\TicTacToeFrame\TicTacToe-BottomRight`
- `Interface\TicTacToeFrame\TicTacToe-TopLeft`
- `Interface\TicTacToeFrame\TicTacToe-TopRight`
### Interface\TimeManager

- `Interface\TimeManager\ClockBackground`
- `Interface\TimeManager\GlobeIcon`
- `Interface\TimeManager\ResetButton`
- `Interface\TimeManager\TimerBackground`
### Interface\TokenFrame

- `Interface\TokenFrame\UI-TokenFrame-CategoryButton`
### Interface\Tooltips

- `Interface\Tooltips\UI-StatusBar-Border`
- `Interface\Tooltips\UI-Tooltip-Background`
- `Interface\Tooltips\UI-Tooltip-Border`
### Interface\TradeFrame

- `Interface\TradeFrame\UI-TradeFrame-BotLeft`
- `Interface\TradeFrame\UI-TradeFrame-BotRight`
- `Interface\TradeFrame\UI-TradeFrame-EnchantIcon`
- `Interface\TradeFrame\UI-TradeFrame-Highlight`
- `Interface\TradeFrame\UI-TradeFrame-TopLeft`
- `Interface\TradeFrame\UI-TradeFrame-TopRight`
### Interface\TradeSkillFrame

- `Interface\TradeSkillFrame\UI-TradeSkill-BotLeft`
- `Interface\TradeSkillFrame\UI-TradeSkill-LinkButton`
### Interface\TutorialFrame

- `Interface\TutorialFrame\TutorialFrameBackground`
- `Interface\TutorialFrame\UI-TUTORIAL-FRAME`
- `Interface\TutorialFrame\UI-TutorialFrame-CalloutGlow`
### Interface\Vehicles

- `Interface\Vehicles\UI-Vehicle-Frame`
- `Interface\Vehicles\UI-Vehicle-Frame-Border`
- `Interface\Vehicles\UI-Vehicle-Frame-Border-Organic`
- `Interface\Vehicles\UI-Vehicles-Button-Exit-Down`
- `Interface\Vehicles\UI-Vehicles-Button-Exit-Up`
- `Interface\Vehicles\UI-Vehicles-Button-Highlight`
- `Interface\Vehicles\UI-Vehicles-Button-Pitch-Down`
- `Interface\Vehicles\UI-Vehicles-Button-Pitch-Up`
- `Interface\Vehicles\UI-Vehicles-Button-PitchDown-Down`
- `Interface\Vehicles\UI-Vehicles-Button-PitchDown-Up`
- `Interface\Vehicles\UI-Vehicles-Elements-Organic`
- `Interface\Vehicles\UI-Vehicles-Endcap`
- `Interface\Vehicles\UI-Vehicles-Endcap-Organic-bottle`
- `Interface\Vehicles\UI-Vehicles-FuelTank`
- `Interface\Vehicles\UI-Vehicles-PartyFrame`
- `Interface\Vehicles\UI-Vehicles-Raid-Icon`
- `Interface\Vehicles\VehicleSeats`
### Interface\WorldMap

- `Interface\WorldMap\Cosmic\Cosmic-Azeroth-Highlight`
- `Interface\WorldMap\Cosmic\Cosmic-Outland-Highlight`
- `Interface\WorldMap\UI-QuestPoi-IconGlow`
- `Interface\WorldMap\UI-QuestPoi-NumberIcons`
- `Interface\WorldMap\UI-World-Icon`
- `Interface\WorldMap\UI-WorldMap-QuestIcon`
- `Interface\WorldMap\UI-WorldMapSmall-Left`
- `Interface\WorldMap\UI-WorldMapSmall-Right`
- `Interface\WorldMap\WorldMap-MagnifyingGlass`
- `Interface\WorldMap\WorldMapPartyIcon`
### Interface\WorldStateFrame

- `Interface\WorldStateFrame\WorldState-CaptureBar`
- `Interface\WorldStateFrame\WorldStateFinalScore-Highlight`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-Bot`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-BotLeft`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-BotRight`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-Top`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-TopBackground`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-TopLeft`
- `Interface\WorldStateFrame\WorldStateFinalScoreFrame-TopRight`
