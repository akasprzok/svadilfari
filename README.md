![main](https://github.com/akasprzok/svadilfari/actions/workflows/main.yml/badge.svg?branch=main)
[![Hex](https://img.shields.io/hexpm/v/svadilfari.svg)](https://hex.pm/packages/svadilfari/)
[![Hex Docs](https://img.shields.io/badge/hex-docs-informational.svg)](https://hexdocs.pm/svadilfari/)
![License](https://img.shields.io/hexpm/l/svadilfari)
[![Coverage Status](https://coveralls.io/repos/github/akasprzok/svadilfari/badge.svg?branch=main)](https://coveralls.io/github/akasprzok/svadilfari?branch=main)

# Svadilfari

A logger backend for sending logs directly to Grafana Loki.

## Installation

The package can be installed by adding `svadilfari` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:svadilfari, "~> 0.1"}
  ]
end
```

Configure some parameters:

```elixir
config :logger, :backends, [:console, Svadilfari]

config :logger, :svadilfari,
  metadata: [:user_id, :bogons],
  max_buffer: 10,
  client: [
    url: "http://localhost:3100",
    opts: [
      org_id: "tenant1"
    ]
  ],
  labels: [
    {"service", "svadilfari"},
    {"env", "dev"}
  ]
```

and start sending logs to Loki!

## Documentation

For detailed documentation, configuration options, and examples, see [hex docs](https://hexdocs.pm/svadilfari).
