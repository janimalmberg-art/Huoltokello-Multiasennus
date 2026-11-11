# -*- coding: utf-8 -*-
"""Kieliaskorjaukset asiakas-esitteeseen (idempotenti)."""
import io

P = r"C:\Users\PC\Desktop\Huoltokello-Multiasennus\Myyntimateriaali\Huoltokello-Esittely-Asiakkaalle.html"

PARIT = [
    ("Ydinhöyhyys", "Ydinarvo"),
    ("tyyppinen", "tyypillinen"),
    ("plannint", "planning"),
    ("energiato,", "energianhallinta,"),
    ("asiakirjaprossuun", "asiakirjaprosessiin"),
    ("julkiseesti", "julkisesti"),
    ("tuotesiviin", "tuotesivuihin"),
    ("modulipohjaiseen", "moduulipohjaiseen"),
    ("niita", "niitä"),
    ("eivät kilpailijoita", "eivät ole kilpailijoita"),
    ("annetaan ilmainen lisä rinnalle", "tarjotaan ilmainen lisä rinnalle"),
    ("ei kirjautumisketju.", "ei usean järjestelmän kirjautumista."),
    ("kellarit, autotallit, verkkokatteet", "kellarit, autotallit, katvealueet"),
    ('"pahan muistaminen" poistuu', "muistamispaine poistuu"),
    ("Työntekija alkaa työn 10 sekunnissa", "Työntekijä aloittaa työn 10 sekunnissa"),
    ("kentälle vapautuu vuodessa (tyypillinen)", "kentältä vapautuu aikaa vuodessa (tyypillinen)"),
    ("rinnalle arvottuna, 0 euron lisällä", "rinnalla kytkeytyvänä, 0 euron lisällä"),
    ("capital-ralli", "capital planning -rooli"),
    ("Selkeät tehtävätteet", "Selkeät tehtävät"),
    ("isoommat painikkeet", "isommat painikkeet"),
    ("tehtava-asiasisältö", "tehtävän asiasisältö"),
    ("riitilöissä", "riidoissa"),
    ("vastuujaoissa", "vastuunjaoissa"),
    ("työt ei pysähdy", "työ ei pysähdy"),
    ("Varmuuskopiot omalla hallinnalla", "Varmuuskopiot omassa hallinnassa"),
    ("(30 uusinta)", "(30 uusinta varmuuskopiota)"),
    ("Ei .NET-latauksia, itsenäinen app", "Ei .NET-latauksia — itsenäinen sovellus"),
    ("Säästö/luotsius", "Säästö/luotettavuus"),
    ("kenttäjäjestelmä", "kenttäjärjestelmä"),
    ("kohde vaikeutuu: integraatio, koulutus, hankinta", "riskeinä: integraatio, koulutus, hankinta"),
    ("aika jää pienemmäksi — työnhallinta ei muutu kentän työkaluksi", "hyöty jää pienemmäksi — isäntä ei muutu kentän työnäytöksi"),
    ("viherrakennet, lämpökatselm, savuhirmajärjestelmän katselmointi...", "viheralueiden hoito, lämmityskatselmus, savuhälytinten tarkistus..."),
    ("QR-kuitin puhalinella", "QR-kuitauksen puhelimella"),
    ("moduulitatiedot", "moduulitiedot"),
    ("Muuttuneiden oletuksien", "Muuttuneiden oletuksen"),
    ("oletuksien", "oletusten"),
    ("eikä syrjivätä", "eikä syrjivä"),
    ("Ennustetyöläisen", "Ennustetyön"),
    ("säästö syntyy\n    rinnalle arvottuna", "säästö syntyy\n    rinnalla kyettenä"),
]

with io.open(P, "r", encoding="utf-8") as f:
    t = f.read()

alku = t
for vanha, uusi in PARIT:
    if vanha != uusi and vanha in t:
        t = t.replace(vanha, uusi)

# rikkoutuneen merkin korjaus
t = t.replace("\ufffd", "✓")

with io.open(P, "w", encoding="utf-8") as f:
    f.write(t)

epailyttavat = ["Ydinh", "plannint", "energiato", "prossu", "julkise", "tuotesivi",
                "modulipohj", "kirjautumisketju", "verkkokatteet", "syrjivätä",
                "oletuksien", "moduulitatiedot", "viherrakennet", "puhalinella",
                "tehtävätteet", "riitil", "vastuujaoissa", "tyyppinen"]
lojattavat = [e for e in epailyttavat if e in t]
print("Muutettiin:", (alku != t))
print("Jäljellä epäilyttävät:", lojattavat if lojattavat else "EI")
print("Merkit yhteensä:", len(t))
