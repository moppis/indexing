# Indexlabben – SQL Server

## Start

Skapa en `.env`-fil i labbmappen och ange `LAB_PASSWORD`(minst åtta tecken och tecken från minst tre av grupperna
versaler, gemener, siffror och specialtecken).

Nu kan vi starta upp sql server genom att köra 
```console
podman compose up -d
```
Databasen kommer att initieras med några tabeller som helt saknar index.

## Anslut till SQL Server

Använd valfritt verktyg för att ansluta till databasen, t.ex
* [SQL Server Management Studio](https://learn.microsoft.com/ssms/install/install)
* [DBeaver Community](https://dbeaver.io/download/)

| Inställning | Värde |
|---|---|
| Värd | `localhost` |
| Port | `14330`, eller porten du valde vid start |
| Databas | `indexlab` |
| Användare | `sa` (SQL Server Authentication) |
| Lösenord | Värdet på `LAB_PASSWORD` i din `.env` |
| Schema | `dbo` |
| Avbild | `mcr.microsoft.com/mssql/server:2025-latest` |

I queries mappen finns det exempel på queries som kan köras för att kolla på data sidor, index statistik mm 


## Avslut

För att avsluta kör
```console
podman compose down
```
