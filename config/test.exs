import Config

config :logger, :backends, [Svadilfari]

config :logger, :svadilfari,
  metadata: [:user_id, :bogons],
  max_buffer: 1,
  client: [
    url: "http://myurl.com",
    opts: [
      org_id: "tenant1"
    ]
  ],
  labels: [
    {"service", "loki"},
    {"cluster", "us-east-1"}
  ]
