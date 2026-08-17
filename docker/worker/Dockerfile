ARG DOTNET_VERSION=10.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}-noble AS restore

WORKDIR /src

COPY ["src/Worker/Worker.csproj", "src/Worker/"]

RUN dotnet restore "src/Worker/Worker.csproj" \
      --runtime linux-x64

FROM restore AS publish

ARG BUILD_CONFIGURATION=Release
ARG VERSION=1.0.0

COPY src/ src/

RUN dotnet publish "src/Worker/Worker.csproj" \
      --configuration ${BUILD_CONFIGURATION} \
      --runtime linux-x64 \
      --self-contained false \
      --no-restore \
      -p:Version=${VERSION} \
      -p:PublishReadyToRun=true \
      --output /app/publish

FROM mcr.microsoft.com/dotnet/runtime:${DOTNET_VERSION}-noble-chiseled AS final

WORKDIR /app

COPY --from=publish --chown=$APP_UID:$APP_UID /app/publish .

USER $APP_UID

ENTRYPOINT ["dotnet", "Worker.dll"]
