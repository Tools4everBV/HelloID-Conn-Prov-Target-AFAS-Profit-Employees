# Voorstel refactor AFAS Employee target connector

## Aanleiding

De AFAS Employee target connector correleert een bestaande AFAS-medewerker en schrijft persoonsgegevens terug die in HelloID worden bepaald, zoals het zakelijk e-mailadres (`EmAd`) en eventueel `EmailPortal`, `TeNr` en `MbNr`. De connector maakt geen medewerkers aan en verwijdert ze niet. AFAS is voor medewerkers tegelijk de bron.

De AFAS User target connector is inmiddels herschreven volgens de laatste conventie (zie de branch `major-upgrade-of-connector` in die repository). Deze connector loopt daarop achter:

* de account reference is een object (`{ Medewerker, Persoonsnummer }`), terwijl de User connector een enkele string gebruikt;
* de GetConnector `T4E_HelloID_Users_v2` gebruikt aliasnamen (`Medewerker`, `Persoonsnummer`, `Email_werk`, `Email_portal`, `Telefoonnr_werk`, `Mobielnr_werk`). Daardoor bevatten update en delete een vaste vertaaltabel en een vaste lijst met ondersteunde velden. Elk extra veld vraagt aanpassing van meerdere scripts;
* update en delete bevatten grotendeels dezelfde code, met geneste try/catch-blokken en foutafhandeling via `finally` op basis van tekst in audit logs;
* de legacy-opties `onlyUpdateOnCorrelate` en `isDebug` (`Write-Verbose`) zijn nog aanwezig;
* filterwaarden worden niet ge-escaped en niet gecontroleerd op komma of puntkomma;
* vrije velden (custom fields) vragen handmatige scriptaanpassingen op drie plekken (zie README).

## Doel

Deze connector gelijktrekken met de nieuwe AFAS User connector, zodat beide connectoren dezelfde opbouw, conventies en beheerervaring hebben.

Doelen:

* `EmId` als account reference (string);
* een eigen target-GetConnector waarvan de veld-id's gelijk zijn aan de AFAS-veldcodes;
* generieke vergelijking van de fieldmapping, zonder vaste veldlijst in de scripts;
* verwijderen van legacy-functionaliteit (`onlyUpdateOnCorrelate`, `isDebug`);
* scripts herschrijven volgens de laatste conventie (zelfde opbouw, foutafhandeling en logging als de User connector);
* import herschrijven volgens de User connector.

Buiten scope:

* aanmaken of verwijderen van medewerkers in AFAS;
* enable/disable en permissions;
* herontwerp van de AFAS source connector;
* OAuth (al doorgevoerd in 4.0.0);
* mTLS met certificaat.

## Ontwerpkeuzes

### 1. Alleen correlatie

Create zoekt de medewerker op `EmId`, met de eis dat `BcCo` niet leeg is. Dit is dezelfde query als in de User connector (`filterfieldids=EmId,BcCo`, `operatortypes=1,9`).

* 1 resultaat: correleren. `EmId` wordt de account reference en de huidige AFAS-waarden worden als account data teruggegeven.
* 0 resultaten: de actie faalt gecontroleerd.
* Meer dan 1 resultaat: de actie faalt.

Create schrijft zelf niets naar AFAS. Direct na de correlatie voert HelloID de update uit, die de gemapte waarden wegschrijft.

### 2. Account reference

* correlatie op `EmId`, het medewerkernummer;
* account reference is `EmId` als string;
* `BcCo` (persoonsnummer) is nodig om in de `KnEmployee`-payload het onderliggende `KnPerson`-record te matchen (`MatchPer = 0`). Het script haalt `BcCo` bij elke actie op uit de GetConnector en slaat het op in de account data, maar het is geen reference.

Vervolgacties zoeken op `EmId`. Er is geen fallback-hercorrelatie.

Deze versie is alleen bedoeld voor nieuwe implementaties. De oude object-reference wordt niet ondersteund en er is geen migratie van bestaande accounts.

### 3. Target-GetConnector

Nieuwe GetConnector `T4E_HelloID_Target_Employees`. De veld-id's zijn gelijk aan de AFAS-veldcodes van `KnEmployee`/`KnPerson`:

| Veld-id     | Omschrijving AFAS                  | Gebruik                                  |
|-------------|------------------------------------|------------------------------------------|
| EmId        | Medewerker                         | Correlatie en account reference          |
| BcCo        | Persoonsnummer                     | `KnPerson`-match in de update payload    |
| Nm          | Naam (weergavenaam)                | Alleen voor de display name bij import   |
| EmAd        | E-mail werk                        | Mappable                                 |
| EmailPortal | E-mail toegang                     | Mappable                                 |
| TeNr        | Telefoonnummer werk                | Mappable                                 |
| MbNr        | Mobiel werk                        | Mappable                                 |

De GetConnector moet één rij per medewerker opleveren. Bij meerdere rijen voor dezelfde `EmId` falen update en delete. De standaardfilter op contractdatums blijft zoals in `T4E_HelloID_Users_v2` (startdatum < vandaag + 3 maanden, einddatum > vandaag − 3 maanden of leeg).

Een veld toevoegen gaat daarmee alleen via de GetConnector en de fieldmapping, met dezelfde veld-id als de AFAS-veldcode. De scripts hoeven niet te worden aangepast.

De `.gcn` wordt in AFAS gebouwd en geëxporteerd en aan de repository toegevoegd. `T4E_HelloID_Users_v2.gcn` wordt verwijderd.

### 4. Fieldmapping

| Veld        | Acties                 | Doel                                                                 |
|-------------|------------------------|----------------------------------------------------------------------|
| EmId        | Create                 | Correlatie op medewerkernummer                                       |
| BcCo        | Create, Update         | Persoonsnummer; scriptmatig gevuld vanuit AFAS (mapping `None`)      |
| EmAd        | Create, Update, Delete | Zakelijk e-mailadres; bij delete standaard leeg (uniek binnen AFAS)  |

`EmailPortal`, `TeNr` en `MbNr` staan niet standaard in de mapping, maar kunnen zonder scriptaanpassing worden toegevoegd.

Regels in de scripts:

* `EmId` en `BcCo` worden nooit in de update payload als veld meegestuurd (`EmId` is het element key, `BcCo` alleen de `KnPerson`-match);
* update stuurt alleen gewijzigde velden mee, zodat de audit log de werkelijke wijzigingen toont. Delete stuurt alle gemapte velden mee, zoals in de User connector. Getest: `KnPerson` accepteert een veld met de huidige waarde, ook als het leeg is;
* een gemapt veld dat niet in de GetConnector staat, kan niet worden vergeleken en wordt stil overgeslagen (zoals in de User connector);
* bij update worden lege gemapte waarden niet weggeschreven (zoals in de User connector). Bij delete juist wel, zodat velden kunnen worden leeggemaakt. AFAS maakt tekstvelden leeg met een lege string, niet met JSON `null`.

### 5. Vrije velden

Vrije velden (`U` + GUID, bijvoorbeeld `U4F2A9C0E1B7D4E3A8F6C5B2D1E0A9F8C`) op de medewerker horen op het niveau van `AfasEmployee` en niet onder `KnPerson`. Velden in de mapping waarvan de naam overeenkomt met `^U[0-9A-Fa-f]{32}$` gaan naar `AfasEmployee.Element.Fields` en alle overige velden naar `KnPerson.Element.Fields`. De GetConnector moet het vrije veld met dezelfde veld-id bevatten. De handmatige instructie in de README vervalt daarmee.

Beperking: een vrij veld op persoonsniveau (`KnPerson`) wordt ook op medewerkerniveau gezet en wordt dus niet ondersteund. Dat vraagt maatwerk.

### 6. Legacy-opties verwijderen

* `onlyUpdateOnCorrelate`: verwijderd. Past niet meer bij de huidige werkwijze en is ook in de User connector verwijderd.
* `isDebug`: verwijderd. Logging gaat via `Write-Information` en `Write-Warning`, zoals in de User connector.

## Lifecycle per actie

### Create / correlate

* medewerker zoeken op `EmId` met een niet-lege `BcCo`;
* `EmId` als account reference teruggeven;
* de huidige AFAS-waarden van de gemapte velden als account data teruggeven.

Geen mutaties in AFAS.

### Update

* medewerker zoeken op de account reference (`EmId`);
* gemapte velden generiek vergelijken met de GetConnector-waarden;
* alleen gewijzigde velden wegschrijven via `KnEmployee` (`PUT`), met `KnPerson`-match op `BcCo`;
* `PreviousData` vullen met de huidige AFAS-waarden en `Data` met de nieuwe waarden;
* niet gevonden: de actie faalt.

### Delete / uncorrelate

* medewerker zoeken op de account reference;
* alle gemapte delete-waarden (standaard `EmAd` leeg) wegschrijven;
* niet gevonden: de actie slaagt, met een audit log dat de medewerker mogelijk al is verwijderd;
* de medewerker zelf wordt nooit verwijderd.

## Reconciliation

Bij een delete vanuit reconciliation is geen fieldmappingdata beschikbaar. Net als in de User connector stuurt een dropdown in de configuratie dit gedrag.

### Reconciliationgedrag bij delete (`DeleteMode`)

| Waarde       | Betekenis                                                        |
|--------------|------------------------------------------------------------------|
| `keepEmAd`   | Geen mutatie in AFAS, `EmAd` behouden; alleen ontkoppelen (standaard) |
| `clearEmAd`  | `EmAd` leegmaken en ontkoppelen                                  |

De standaard is `keepEmAd`: de medewerker is ook brondata, en het automatisch leegmaken van het e-mailadres van een medewerker die niet (meer) in HelloID voorkomt is riskant. Een reguliere delete gebruikt de fieldmapping.

## Import

Herschreven volgens de User connector:

* paginering met `skip`/`take` in een `do`/`while`, zonder tussenopslag van alle records;
* filter: `EmAd` niet leeg (een medewerker met een zakelijk e-mailadres geldt als account);
* account reference `EmId`, display name `Nm` (fallback `EmId`, maximaal 100 tekens), username `EmAd`;
* een waarschuwing bij dubbele `EmId`; elke medewerker wordt maar één keer teruggegeven;
* `Enabled` blijft `$false`, omdat de connector geen enable/disable kent.

## Configuratie

| Key             | Wijziging                                                            |
|-----------------|----------------------------------------------------------------------|
| BaseUri         | Ongewijzigd, beschrijving toegevoegd                                 |
| ClientId        | Ongewijzigd                                                          |
| ClientSecret    | Ongewijzigd                                                          |
| GetConnector    | Standaardwaarde `T4E_HelloID_Target_Employees`, beschrijving toegevoegd |
| UpdateConnector | Ongewijzigd (`KnEmployee`), beschrijving toegevoegd                  |
| DeleteMode      | Nieuw: reconciliationgedrag bij delete (`keepEmAd`, `clearEmAd`)     |
| onlyUpdateOnCorrelate | Verwijderd                                                     |
| isDebug         | Verwijderd                                                           |

## Versie

Dit is een breaking change (account reference, GetConnector, fieldmapping en configuratie). Nieuwe versie: `5.0.0`.