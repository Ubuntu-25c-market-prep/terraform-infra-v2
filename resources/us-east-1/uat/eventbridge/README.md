# eventbridge - event rules

Rules on the default event bus, one per entry in `config.yaml` `rules`,
merged over `rule_defaults`. `name` is the full rule name,
`<env>-eventbridge-<name>-<region>`, at most 64 characters.

## Adding a rule

1. Add an entry under `rules` in `config.yaml` with either
   `event_pattern` or `schedule_expression`, and its `targets`.
2. Let the target accept events: for a queue, `events.amazonaws.com` in
   its `send_services` (`../sqs/config.yaml`).
3. Open a PR with `- Path: /resources/us-east-1/uat/eventbridge` in the
   commit message; merge applies it.

## Keys

| Key | Meaning |
|---|---|
| `rules[].name` | required, the full rule name; changing it recreates the rule |
| `description` | optional |
| `enabled` | `false` keeps the rule but stops it matching |
| `event_pattern` | the pattern as YAML, same keys as the JSON (`source`, `detail-type`, `detail`, ...) |
| `schedule_expression` | `rate(...)` or `cron(...)`, instead of a pattern |
| `targets[]` | `id` (unique within the rule) and `arn` of the target |

## Outputs

`rule_arns` - map keyed by the rule name.
