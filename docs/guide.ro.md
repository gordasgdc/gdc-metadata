# GDC Metadata — Ghid de utilizare

## Folder → inspector → Media Pool

1. **Deschideți un folder** (butonul folder din bară). Aplicația îl scanează doar pentru citire și listează clipurile: cameră, timecode etc.
2. **Inspector.** Selectați un clip: cameră, obiectiv, balans de alb, expunere, profil de imagine. Fiecare valoare își arată sursa (etichetă din clip, derivată, indisponibilă). Căutați după câmp sau valoare; bannerul explică de ce se potrivește un clip.
3. **Trimite în Resolve.** Deschideți întâi un proiect în Resolve. Fereastra previzualizează, pe clip, ce se scrie, ce se păstrează și ce e identic.
4. **Aplică în Media Pool** scrie valorile.

## Gamut de intrare și curbă de transfer

Cele două valori de sus din inspector spun ce intrare alegi în color management: de exemplu un clip Canon C50 arată **Cinema Gamut** + **Canon Log 2** (citit din pista `cndm` a fișierului) — în Resolve alegi *Canon Cinema Gamut / Canon Log 2*; un clip Canon Log 3 arată **Canon Log 3**. Fiecare valoare are sursa ei; fără dovezi rândul spune **Indisponibil** și nu se atribuie nimic. Resolve detectează singur multe clipuri Canon la import. **Aplică în Media Pool** scrie doar note informative (Gamma Notes / Color Space Notes); **Setează spațiul de intrare…** este o acțiune separată, cu confirmare, care schimbă procesarea culorii, funcționează în proiecte DaVinci YRGB Color Managed și nu suprascrie o alegere existentă. Manual: Project Settings ▸ Color Management ▸ DaVinci YRGB Color Managed, apoi Media Pool ▸ clic dreapta pe clip ▸ Input Color Space.

## Ce face «Aplică» (verificat în Resolve, după închiderea și redeschiderea proiectului)

- Câmp gol → se scrie.
- Câmp care are deja valoare → se păstrează (nu se suprascrie).
- Același clip în mai multe bin-uri → ambiguu, nu se aplică.
- Clipurile se potrivesc după calea reală a fișierului, deci și folderele accesate prin legături.

## CSV ca alternativă

- Salvați CSV-ul din fereastră, apoi în Resolve: File → Import Metadata To → Media Pool…
- Opțiuni verificate: bifați **Match using filename**; lăsați **Match using clip start and end Timecode** nebifat (bifat, Resolve a raportat că nu găsește potriviri pentru CSV-ul nostru); Reel Name nebifat; la îmbinare **Only update metadata items with entries in the source file**.
- **Atenție:** importul suprascrie valorile existente.
- **Nume de fișier duplicate:** Resolve potrivește după nume, deci fiecare clip cu acel nume (în orice bin, chiar din foldere diferite) primește aceleași valori. Folosiți «Aplică în Media Pool» ca să evitați asta.

## Mișcare și stabilizare

- Inspectorul listează datele de mișcare detectate (telemetrie din clip, jurnale externe, proiecte .gyroflow) și unde au fost găsite.
- Sursele apar ca **Compatibilitate Gyroflow neverificată**. Stabilizarea nu este oferită: nu există încă un traseu demonstrat înainte/după în Resolve.

## Mai multe clipuri, foldere, al doilea lot

- **Trage clipuri sau un folder** peste fereastră, într-un singur gest și oricâte. Sau **Alege folderul…** (⌘O) și selectează mai multe fișiere și foldere deodată.
- Un import nou se **adaugă** la listă; primul lot se păstrează. **File → Golește lista** o ia de la zero.
- Bara de jos spune câte clipuri au fost importate; dacă un fișier a fost respins, apasă „importate · respinse” pentru motivul fiecăruia.
- Clipurile cu același nume din foldere diferite rămân separate.

## Fereastră largă, fereastră îngustă, cadru mare

La fereastră largă lista e un tabel: Clip (cu miniatură), Gamut / curbă, Cameră, Obiectiv, Balans de alb, Expunere, Timecode. La fereastră îngustă rămân Clip, Gamut / curbă și Timecode-ul complet. **Mărește cadrul** (sau dublu clic pe previzualizare) deschide un cadru static mare; **Esc** îl închide, iar selecția, clipul activ, filtrul și poziția în tabel rămân.

## Exemplu: un lot Sony spre Resolve

1. Selectează două clipuri (clic, ⌘-clic; sau Tab pe tabel și Shift+↓). Bara arată „2 selectate din 3”.
2. **Trimite 2 în Resolve** → vezi pe fiecare rând câte câmpuri se scriu și câte se păstrează → **Aplică în Media Pool** (doar metadate informative).
3. Separat: **Setează spațiul de intrare…** → confirmă pentru cele 2 clipuri (schimbă procesarea culorii).
4. Salvează și redeschide proiectul în Resolve și compară.

## Versiune și actualizări

- Versiunea instalată e în bara de jos și în **Despre GDC Metadata** (versiune și build).
- **Caută actualizări…** (meniul aplicației) răspunde mereu: versiune nouă, „Ești la zi” sau „Nu am putut verifica” cu motivul. **Actualizează acum** descarcă, verifică, instalează și repornește aplicația.
- Vii de la 0.1.0 (fără actualizator): instalează o singură dată noul DMG; apoi actualizezi din aplicație.

## Manual complet

- Manual PDF complet: butonul / meniul **Ajutor**, sau https://gordas.dev/gdc-metadata/GDC-Metadata-Manual-ro.pdf


**Lot de clipuri (0.3.0).** Selectează cu clic/Shift/⌘/⌘A, apasă **Acceptă pentru export** (fiecare clip își păstrează perechea; se poate anula), apoi **Exportă N clipuri** sau **Trimite N în Resolve** — exact pe selecție. **Scoate din listă** (⌘⌫) și **Golește lista** (⇧⌘⌫) afectează doar lista. Valorile necitite apar ca **Nedetectat**, nu ca „lipsă”. Sony: curba și gamutul se citesc din metadatele încorporate; S-Gamut3.Cine ≠ S-Gamut3.
