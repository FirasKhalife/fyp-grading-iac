export interface UserDataInput {
  readonly region: string;
  readonly composeRepoUrl: string;
  /** Secret name -> Secrets Manager ARN. Only ARNs are embedded, never values. */
  readonly secretArns: Record<string, string>;
}

/** Boot script. Contains no secret values: the instance role fetches them at startup. */
export function renderUserData(input: UserDataInput): string {
  const fetchLines = Object.entries(input.secretArns)
    .map(
      ([name, arn]) =>
        `echo "${name.toUpperCase()}=$(aws secretsmanager get-secret-value --region ${input.region} ` +
        `--secret-id '${arn}' --query SecretString --output text)" >> /opt/fyp/.env`,
    )
    .join("\n");

  return `#!/bin/bash
set -euo pipefail

dnf install -y docker git
systemctl enable --now docker

mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \\
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

git clone --depth 1 "${input.composeRepoUrl}" /opt/fyp

umask 077
: > /opt/fyp/.env
${fetchLines}

cat > /etc/systemd/system/fyp.service <<'UNIT'
[Unit]
Description=FYP grading platform (docker compose)
After=docker.service network-online.target
Requires=docker.service

[Service]
WorkingDirectory=/opt/fyp
ExecStart=/usr/bin/docker compose --env-file /opt/fyp/.env up
ExecStop=/usr/bin/docker compose down
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now fyp.service
`;
}
