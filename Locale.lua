local _, ns = ...

-- Localisation : le MECANISME. Les tables de traduction vivent dans `Locale/<code>.lua`,
-- charges apres celui-ci.
--
-- La cle EST le texte anglais : toute chaine non traduite retombe donc naturellement sur
-- l'anglais, sans trou d'affichage. L'anglais n'a par consequent pas de fichier — il n'y
-- aurait que des cles egales a leurs valeurs.
--
-- Les 400 lignes de francais etaient ici, avec le mecanisme. Un fichier ou l'on ajoute une
-- chaine chaque jour et un fichier qui ne bouge jamais n'ont pas la meme duree de vie, et
-- la separation est ce qui rend l'ajout d'une troisieme langue mecanique : un fichier de
-- plus, une ligne dans `CLIENT_MAP`, une dans `ns.LANGUAGES`, une dans le .toc.

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.L = L

-- Rempli par les fichiers de `Locale/`. Il doit exister AVANT eux : le .toc les charge
-- dans cet ordre, et une inversion donnerait un `attempt to index nil` au chargement.
local translations = {}
ns.translations = translations

-- Anglais et francais uniquement.
--
-- Il y avait ici trois blocs de plus — de, it, es — a 65 cles chacun contre 330 pour
-- le francais. Comme la cle EST le texte anglais, les 265 cles absentes retombaient
-- sur l'anglais : un joueur allemand obtenait une interface a 20 % allemande, ce qui
-- se lit comme un addon casse, pas comme un addon anglais. Mieux vaut deux langues
-- completes que cinq dont trois a moitie. Une langue se rajoute quand quelqu'un la
-- traduit en entier, et `tools/check_locale.py` verifie la couverture.
local CLIENT_MAP = {
    frFR = "fr",
}

ns.LANGUAGES = { "auto", "en", "fr" }

--- Langue effective : le reglage explicite, sinon celle du client, sinon l'anglais.
function ns.CurrentLanguage()
    local setting = ns.db and ns.db.language or "auto"
    if setting and setting ~= "auto" then return setting end
    return CLIENT_MAP[GetLocale()] or "en"
end

-- Widgets dont le libelle doit suivre la langue.
--
-- Tout texte pose dans un `Create()` n'etait jamais repose : onglets, boutons de
-- l'entete, titres des cartes d'aide, boutons de l'onglet Guilde. `/sa lang fr` laissait
-- donc la moitie de la fenetre en anglais jusqu'au prochain /reload, et l'appel a
-- `UI.Show()` cense regler ca ne touchait aucun de ces FontStrings.
local retranslate = {}

--- Pose un libelle traduit et retient le widget pour les changements de langue.
--- @param setter string|nil methode a appeler, `SetText` par defaut
function ns.Localize(widget, key, setter)
    if not widget or not key then return widget end
    setter = setter or "SetText"
    if type(widget[setter]) ~= "function" then return widget end

    table.insert(retranslate, { widget = widget, key = key, setter = setter })
    widget[setter](widget, L[key])
    return widget
end

--- Recharge la table de traduction active, puis repose tous les libelles enregistres.
function ns.ApplyLanguage()
    for key in pairs(L) do L[key] = nil end

    local code = ns.CurrentLanguage()
    local table_ = translations[code]
    if table_ then
        for key, value in pairs(table_) do
            L[key] = value
        end
    end

    for _, item in ipairs(retranslate) do
        -- Sous pcall : un widget detruit ou un setter disparu ne doit pas empecher les
        -- suivants d'etre retraduits.
        pcall(item.widget[item.setter], item.widget, L[item.key])
    end

    return code
end
