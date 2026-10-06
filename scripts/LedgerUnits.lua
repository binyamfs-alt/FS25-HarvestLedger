-- All display conversions belong to the game's current local player settings.
-- Persisted measurements and CSV columns keep their original, explicit units.
local H = HarvestLedger

function H:displayArea(sqm)
    return g_i18n:formatArea((sqm or 0) / 10000, 2)
end

function H:displayVolume(liters)
    return g_i18n:formatVolume(liters or 0, 0)
end

function H:displayRate(liters, sqm)
    if not sqm or sqm <= 0 then
        return "--"
    end
    -- Convert the denominator first, then let the game's volume formatter
    -- convert the numerator. This also handles independent area/volume choices.
    local area = g_i18n:getArea(sqm / 10000)
    return g_i18n:formatVolume((liters or 0) / area, 0) .. "/" .. g_i18n:getAreaUnit()
end

function H:unitSignature()
    return g_i18n:formatArea(1, 2) .. "|" .. g_i18n:formatVolume(1000, 0)
end
