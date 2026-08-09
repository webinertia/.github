# Security Policy

## Reporting a Vulnerability

If you believe you have found a security vulnerability in a project maintained
by Webinertia, please **do not open a public issue**. Instead,
report it privately using [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately):

1. Go to the affected repository on GitHub.
2. Open the **Security** tab.
3. Click **Report a vulnerability** (under "Advisories").
4. Fill out the advisory form with as much detail as you can, including:
   - The affected package/repository and version(s)
   - Steps to reproduce the issue
   - A summary of the vulnerability and its potential impact
   - A suggested fix or mitigation, if you have one

## What to Expect

- We will investigate and work with you to confirm the vulnerability.
- We will not disclose the issue publicly, and ask that you do the same,
  until a fix has been released.

## Our Policy Once a Vulnerability Is Confirmed

- We will patch the current release branch, as well as the immediate prior minor release branch.
- We will issue new patch releases for each affected branch as soon as a fix is ready.
- We will publish a GitHub Security Advisory (GHSA) on the affected repository detailing the vulnerability, affected versions, and remediation steps, crediting the reporter unless anonymity is requested.
