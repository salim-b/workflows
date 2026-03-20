# [GitHub Actions workflows](https://docs.github.com/de/actions/reference/workflows-and-actions) for office automation

## Newsletter draft

This workflow runs on the second Wednesday of every month. It composes a draft for the monthly newsletter from *Digitale Gesellschaft Schweiz* using generative AI and writes the result to a new page in our [Confluence instance](https://wiki.digitale-gesellschaft.ch/).

The workflow is defined in [`.github/workflows/newsletter_draft.yml`](.github/workflows/newsletter_draft.yml).

- It executes the Bash script [`mise-tasks/newsletter_draft.sh`](mise-tasks/newsletter_draft.sh) via `mise run newsletter_draft`. The script executes a Codename Goose [recipe](https://block.github.io/goose/docs/guides/recipes/recipe-reference) stored under `.goose/recipes/`.
- It uses a cron schedule [`0 0 * * 3`](.github/workflows/newsletter_draft.yml#L7) (every Wednesday) and then filters for the second Wednesday (days 8-14 of the month).
- It can be manually triggered from the [**Actions** tab](https://github.com/DigitaleGesellschaft/workflows/actions/workflows/newsletter_draft.yml) in GitHub (e.g. for testing).

### Configuration

 Edit the Goose recipe [`.goose/recipes/newsletter_draft.yaml`](.goose/recipes/newsletter_draft.yaml) and the environment variables in [`config.env`](config.env) to customize the task execution. Note that the script automatically determines suitable `ARTICLE_LINKS` and `NEWSLETTER_LINKS` if none are provided.
