local addonName, addon = ...

-- Italian translations
local L = LibStub("AceLocale-3.0"):NewLocale("KRT", "itIT")
if not L then return end

-- ==================== General Buttons ==================== --
L.BtnConfig    = "Configura"
L.BtnConfigure = "Configurazione"
L.BtnConfirm   = "Conferma"
L.BtnDefaults  = "Predefiniti"
L.BtnEdit      = "Modifica"
L.BtnOK        = "OK"
L.BtnStop      = "Ferma"
L.BtnResume    = "Riprendi"

-- ==================== Minimap Button ==================== --
L.StrMinimapLClick = "|cffffd700Click Sinistro|r per il menu"
L.StrMinimapRClick = "|cffffd700Click Destro|r per le opzioni"
L.StrMinimapSClick = "|cffffd700Shift+Click|r per spostare"
L.StrMinimapAClick = "|cffffd700Alt+Click|r per trascinare liberamente"
L.StrLootHistory   = "Storico Bottino"
L.StrRaidWarnings  = "Avvisi Incursione"
L.StrLFMSpam       = "Spam LFM"
L.StrMSChanges     = "Cambi MS"
L.StrLootBans      = "Divieti Bottino"
L.StrSpamBans      = "Divieti Spam"
