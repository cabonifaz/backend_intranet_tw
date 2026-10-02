FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/TW.Intranet.API/TW.Intranet.API.csproj -c Release -o /app/out

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/out .
CMD ASPNETCORE_URLS=http://0.0.0.0:${PORT:-8080} dotnet TW.Intranet.API.dll