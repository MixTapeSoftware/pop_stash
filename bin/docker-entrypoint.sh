#!/bin/bash
set -e

echo "Installing dependencies..."
mix deps.get

echo "Installing assets..."
mix assets.setup || true

echo "Setting up database..."
mix ecto.create -r PopStash.Repo || true
mix ecto.migrate -r PopStash.Repo || true

echo "Starting Phoenix server..."
exec "$@"
