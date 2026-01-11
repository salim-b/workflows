# [GitHub Actions workflows](https://docs.github.com/de/actions/reference/workflows-and-actions) for office automation

## Newsletter draft

This workflow runs on the second Sunday of every month. It fetches a response from an AI model via OpenRouter and creates a new page in our [Confluence instance](https://wiki.digitale-gesellschaft.ch/).

### Setup instructions

#### 1. Confluence API token

- Log in to your Atlassian account.
- Go to **Account Settings** > **Security** > **Create and manage API tokens**.
- Create a new token and save it.

#### 2. GitHub secrets

In your GitHub repository, go to **Settings** > **Secrets and variables** > **Actions** and add all the environment variables listed in the [`scripts/ai_to_confluence.sh`](scripts/ai_to_confluence.sh) header as secrets.

#### 3. Workflow configuration

- The workflow is defined in `.github/workflows/newsletter_draft.yml`.
- It executes the Bash script `scripts/ai_to_confluence.sh`.
- It uses a cron schedule `0 0 * * 0` (every Sunday) and then filters for the second Sunday (days 8-14 of the month).
- It can be manually triggered from the **Actions** tab in GitHub (e.g. for testing).
