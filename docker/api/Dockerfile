ARG DOTNET_VERSION=10.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}-noble AS restore

WORKDIR /src

COPY ["src/Api/Api.csproj", "src/Api/"]

RUN dotnet restore "src/Api/Api.csproj" \
      --runtime linux-x64

FROM restore AS publish

ARG BUILD_CONFIGURATION=Release
ARG VERSION=1.0.0

COPY src/ src/

RUN dotnet publish "src/Api/Api.csproj" \
      --configuration ${BUILD_CONFIGURATION} \
      --runtime linux-x64 \
      --self-contained false \
      --no-restore \
      -p:Version=${VERSION} \
      -p:PublishReadyToRun=true \
      --output /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled AS final

WORKDIR /app

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_EnableDiagnostics=0

COPY --from=publish --chown=$APP_UID:$APP_UID /app/publish .

USER $APP_UID

EXPOSE 8080

ENTRYPOINT ["dotnet", "Api.dll"]
