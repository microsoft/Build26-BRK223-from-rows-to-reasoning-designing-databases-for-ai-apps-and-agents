# BRK223 cloud DAB image.
#
# Built by `az acr build` from this directory (the orchestrator uploads
# dab-config.json + this Dockerfile to ACR and runs the build server-side
# so attendees don't need a local Docker daemon).
#
# The upstream DAB image already:
#   - exposes port 5000
#   - defaults its working dir to /App
#   - reads /App/dab-config.json on startup
#   - resolves `@env('MSSQL_CONNECTION_STRING')` from the container env
#
# So we only need to bake in the cloud config and we're done.
FROM mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc

# Bake the cloud DAB config into the image. ACA injects
# MSSQL_CONNECTION_STRING via secretRef at runtime.
COPY dab-config.json /App/dab-config.json
