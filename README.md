# Srovnání extensions.conf / .ael / .lua
##


## 1. Úvod

**Asterisk** je open-source softwarová telefonní ústředna umožňující vytváření a provozování telekomunikačních systémů založených na technologii VoIP (Voice over Internet Protocol). Jednou z jejích základních součástí je **dialplan**, který definuje způsob zpracování, směrování a řízení telefonních hovorů [1].

Asterisk umožňuje implementovat dialplan několika způsoby. Vedle tradičního konfiguračního jazyka využívajícího soubor `extensions.conf` podporuje také specializovaný jazyk AEL (Asterisk Extension Language) a programovací jazyk Lua. Jednotlivé přístupy se odlišují syntaxí, strukturou, způsobem zpracování instrukcí a dostupnými programovacími prostředky [2].

Tento projekt se zabývá teoretickým a experimentálním porovnáním uvedených způsobů implementace dialplanu. Důraz je kladen zejména na funkční ekvivalenci, čitelnost zdrojového kódu, náročnost implementace a hardwarovou náročnost při zpracování telefonních hovorů.

Součástí projektu je rovněž automatizace instalace, konfigurace, testování a sběru naměřených dat s cílem zajistit reprodukovatelnost experimentů.

---

## 2. Cíle projektu

Hlavním cílem projektu je **porovnat tři způsoby implementace dialplanu v telefonní ústředně Asterisk** a vyhodnotit jejich vlastnosti z hlediska praktického využití, funkčnosti a výkonnosti.

### 2.1 Dílčí cíle

- Analyzovat jednotlivé způsoby implementace dialplanu.
- Implementovat funkčně ekvivalentní dialplany ve všech třech variantách.
- Porovnat syntaxi, strukturu a čitelnost zdrojového kódu.
- Posoudit náročnost implementace, konfigurace a následné údržby.
- Ověřit funkční správnost jednotlivých implementací.
- Porovnat využití procesoru (CPU).
- Porovnat využití operační paměti (RAM).
- Vyhodnotit chování jednotlivých implementací při zátěži.
- Automatizovat instalaci a konfiguraci testovacího prostředí.
- Automatizovat průběh testování a sběr naměřených dat.
- Zajistit reprodukovatelnost provedených experimentů.
- Vyhodnotit výhody, nevýhody a vhodnost jednotlivých implementací pro praktické využití.

---

## 3. Současný stav problematiky

Dialplan představuje základní prostředek pro definování aplikační logiky telefonní ústředny Asterisk. Umožňuje řídit průběh telefonního hovoru, vykonávat jednotlivé aplikace, pracovat s proměnnými a rozhodovat o dalším směrování hovoru [1].

Existence několika způsobů implementace dialplanu umožňuje přizpůsobit jeho tvorbu požadavkům konkrétního telekomunikačního systému. Zároveň však vzniká otázka, který z dostupných přístupů je nejvhodnější z hlediska vývoje, dlouhodobé údržby a provozní efektivity.

### 3.1 Tradiční dialplan – `extensions.conf`

Tradiční dialplan využívá nativní konfigurační jazyk Asterisku. Jeho struktura je založena na **kontextech** (*contexts*), **rozšířeních** (*extensions*) a **prioritách** (*priorities*), které určují posloupnost vykonávaných instrukcí [3].

Tento přístup představuje základní způsob konfigurace dialplanu. U rozsáhlejších implementací s komplexní aplikační logikou však může být zápis obtížnější na orientaci a následnou údržbu.

### 3.2 Asterisk Extension Language – AEL - extensions.ael

**AEL (Asterisk Extension Language)** je specializovaný jazyk určený pro tvorbu dialplanu v Asterisku. Poskytuje vyšší úroveň abstrakce a umožňuje strukturovanější zápis aplikační logiky pomocí programovacích konstrukcí, jako jsou podmínky, cykly a další prostředky řízení toku programu.

Zdrojový kód AEL je převáděn do interní reprezentace dialplanu založené na rozšířeních a prioritách Asterisku [4].

### 3.3 Lua – `extensions.lua`

Asterisk umožňuje prostřednictvím modulu `pbx_lua` implementovat dialplan v programovacím jazyce Lua. Tento přístup poskytuje možnost využívat standardní programovací konstrukce jazyka Lua při současném přístupu k aplikacím a funkcím telefonní ústředny [5].

Lua umožňuje vytvářet vlastní funkce, pracovat s datovými strukturami a využívat obecné programovací prostředky. Díky tomu představuje alternativu zejména pro implementaci komplexnější aplikační logiky.

### 3.4 Problematika výkonnosti

Odlišný způsob zápisu a interního zpracování jednotlivých implementací může ovlivňovat jejich provozní vlastnosti. Samotné architektonické a syntaktické rozdíly však nejsou dostatečným důkazem vyšší výkonnosti některého z přístupů.

Výkonnost telefonní ústředny může být ovlivněna také konfigurací systému, hardwarovými prostředky, charakterem telefonního provozu a dalšími faktory [6].

Z tohoto důvodu je nutné provést experimentální měření za srovnatelných podmínek, při kterých budou jednotlivé implementace vykonávat funkčně ekvivalentní operace.

Pro generování testovacího SIP provozu bude využit nástroj **SIPp**, který umožňuje vytváření testovacích scénářů, nastavování intenzity provozu a zaznamenávání statistických údajů o průběhu testování [7].

Výsledkem experimentálního měření bude porovnání funkčnosti, hardwarové náročnosti a provozního chování jednotlivých implementací dialplanu.

---
