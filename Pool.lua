local _, ns = ...

local Pool = {}
ns.Pool = Pool

-- Pool de widgets, partage par les vues.
--
-- Les vues reconstruisent leur contenu a chaque affichage : rien n'est detruit, tout est
-- masque puis reutilise. Creer et jeter des cadres a chaque rafraichissement laisserait
-- le ramasse-miettes travailler pendant que le joueur fait defiler une liste.
--
-- GearView et RaidView avaient chacune leur copie de ce code, identiques au caractere
-- pres. Et l'une d'elles a produit un bug que l'autre aurait produit aussi : la carte
-- « Rien a corriger » sortait du pool des cartes de probleme sans que sa ligne de gestes
-- soit videe, donc « clic gauche : detail · clic droit : ignorer » restait affiche sous
-- un message qui ne repondait a aucun clic.
--
-- D'ou le `reset` : une fabrique declare comment remettre son widget a neuf, et le pool
-- s'en charge. Le defaut est de ne rien faire — c'est a la fabrique de savoir quels
-- champs survivent d'un usage a l'autre.

--- Cree un pool.
--- @param factory function fabrique un widget neuf
--- @param reset function|nil remet un widget recycle dans son etat de sortie d'usine
function Pool.New(factory, reset)
    local pool = { items = {}, used = 0, factory = factory, reset = reset }

    --- Masque tout et repart de zero. A appeler en tete de chaque rendu.
    function pool:Reset()
        for _, widget in ipairs(self.items) do widget:Hide() end
        self.used = 0
    end

    --- Rend le prochain widget disponible, visible et remis a neuf.
    function pool:Acquire()
        self.used = self.used + 1
        local widget = self.items[self.used]
        if not widget then
            widget = self.factory()
            self.items[self.used] = widget
        elseif self.reset then
            self.reset(widget)
        end
        widget:Show()
        return widget
    end

    return pool
end

--- Reinitialise en bloc un ensemble de pools nommes.
function Pool.ResetAll(pools)
    for _, pool in pairs(pools) do pool:Reset() end
end
