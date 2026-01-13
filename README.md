# [GitHub Actions workflows](https://docs.github.com/de/actions/reference/workflows-and-actions) for office automation

## Newsletter draft

This workflow runs on the second Wednesday of every month. It fetches a response from an AI model via OpenRouter and creates a new page in our [Confluence instance](https://wiki.digitale-gesellschaft.ch/).

The workflow is defined in [`.github/workflows/newsletter_draft.yml`](.github/workflows/newsletter_draft.yml).

- It executes the Bash script [`scripts/newsletter_draft.sh`](scripts/newsletter_draft.sh).
- It uses a cron schedule [`0 0 * * 3`](.github/workflows/newsletter_draft.yml#L7) (every Wednesday) and then filters for the second Wednesday (days 8-14 of the month).
- It can be manually triggered from the [**Actions** tab](https://github.com/DigitaleGesellschaft/workflows/actions/workflows/newsletter_draft.yml) in GitHub (e.g. for testing).

### Configuration

 Edit the environment variables in [`config.env`](config.env) to customize the script execution. We primarily want to change `OPENROUTER_MODEL` and `OPENROUTER_PROMPT` to further improve on the results. Note that the script automatically appends a section for `ARTICLE_LINKS` and `NEWSLETTER_LINKS` each to the specified `OPENROUTER_PROMPT`.
