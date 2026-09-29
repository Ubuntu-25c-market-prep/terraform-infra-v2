# sqs - queues

Standard queues, one per entry in `config.yaml` `queues`, merged over
`queue_defaults`. Every queue is encrypted and TLS-only. `name` is the
full queue name, `<env>-sqs-<name>-<region>`. FIFO and dead-letter queues
are not implemented.

## Adding a queue

1. Add an entry under `queues` in `config.yaml`.
2. Open a PR with `- Path: /resources/us-east-1/prod/sqs` in the commit
   message; merge applies it. Read the ARN from the `queue_arns` output.
3. Give access: a role in this account needs an IAM policy naming the
   ARN (`../iam/policies/`); an AWS service that sends by itself goes in
   `send_services`.

## Keys

| Key | Meaning |
|---|---|
| `queues[].name` | required, the full queue name, at most 80 characters; changing it recreates the queue |
| `message_retention_seconds` | how long an unread message is kept, 60 to 1209600 |
| `visibility_timeout_seconds` | how long a received message stays hidden from other readers |
| `receive_wait_time_seconds` | 0 = short polling, up to 20 = long polling |
| `kms_key_id` | `null` = SQS-managed encryption; a KMS key ARN = customer-managed |
| `send_services` | AWS service principals allowed to send, e.g. `events.amazonaws.com` |

## Outputs

`queue_arns`, `queue_urls` - maps keyed by the queue name.
