# Penguistics
## Report photos and bucket CORS

`GET /city/reports/{id}/photo` checks the CityStaff group and the caller's assigned
city before returning a five-minute S3 GET URL. The bucket stays private.

The photo bucket is external to the SAM stack. When deploying, review its existing
CORS rules and merge the rules in `Backend/s3-cors.json`, preserving any other
origins still in use. Applying a CORS configuration replaces the previous rules.
The configuration preserves the existing upload rule and allows photo reads from
the sites and localhost ports 5000 (civilian) and 5001 (city). Run Flutter with
`--web-port=5000` or `--web-port=5001`, respectively.
CORS permits browser access; it does not grant S3 permissions.
No bucket changes are applied automatically by the application.

A civic pipeline for civilians to report issues on the road, the system will validate the legitimacy of the report, Store it, and display it on the city worker cite with the optimal routes and course of action

## Custom API domain and shared certificate (#24)

Deploy `Backend/template.yaml` in **us-east-1**, using the existing `penguistics`
stack and `RootDomainName=penguistics.com` (the default). It requests one DNS-validated
certificate for `penguistics.com` and `*.penguistics.com` and maps
`https://api.penguistics.com` to the existing API's default stage.

The first deployment needs two manual DNS steps. Open Namecheap → Domain List →
Manage `penguistics.com` → Advanced DNS before starting.

1. Build and deploy from `Backend` using `sam build` and `sam deploy`. Review the
   change set. While CloudFormation waits on `SharedDomainCertificate`, open ACM
   in us-east-1 and find the pending certificate for `penguistics.com`.
2. Copy its DNS validation CNAME record into Namecheap. For Host, use the record
   name without the trailing `.penguistics.com`; for Value, use the full ACM
   validation hostname. Choose Automatic TTL. The root and wildcard normally
   share a validation record; add each distinct record ACM lists.
3. Leave the validation record in DNS for automatic certificate renewal. Once
   ACM reports Issued, CloudFormation can finish the domain and mapping.
4. From the stack outputs, copy `ApiDnsTarget`. Add a second Namecheap CNAME:
   Host `api`, Value the full `ApiDnsTarget` hostname, TTL Automatic. Do not use
   an `https://` prefix or a path. Replace a conflicting record for `api` only;
   preserve unrelated DNS records.
5. After DNS propagates, check `https://api.penguistics.com/health` for the health
   response. The `GeneratedApiBaseUrl` output continues to work during setup.

Run the city app from `Frontend-City/penguincity`:

```powershell
flutter run -d edge --web-port=5001 --dart-define=PEN_API=https://api.penguistics.com
```

Run the civilian app from `Frontend-Civilian/penguinspotter`:

```powershell
flutter run -d edge --web-port=5000 --dart-define=PEN_API=https://api.penguistics.com --dart-define=SIGNUP_CANCEL_URL=https://api.penguistics.com/signup/cancel
```

Restart Flutter fully when changing defines. Keep using the generated endpoint
until the custom domain's health check succeeds. Both endpoints reach the same API
and use the same Cognito accounts. Reuse `SharedCertificateArn` when implementing
the website hosting tickets. The certificate is retained on stack deletion because
other hosting stacks may depend on it; inventory retained certificates before
recreating the stack to avoid requesting duplicates. The API domain and mapping
are recreated with the API stack, so update the Namecheap `api` target after a
recreation. A permanent name does not preserve database data or Cognito accounts.

## Creating city staff accounts

City staff can't sign up in an app. An admin creates each account by invoking `CreateStaffFunction`
(its name is the `CreateStaffFunctionName` stack output). It creates the Cognito user, adds it to the
`CityStaff` group, and saves the city the account works for.

1. Write the account details to a file, e.g. `staff.json`:

   ```json
   {
     "username": "jdoe-slc",
     "email": "jdoe@example.gov",
     "firstname": "Jane",
     "lastname": "Doe",
     "city": "Salt Lake City",
     "state": "UT"
   }
   ```

   - `city` must be spelled the way it appears on a map ("Salt Lake City", not "SLC"), because it is
     matched against the city each report's coordinates are in. Capitalization and extra spaces don't matter.
   - `state` can be a US state name or abbreviation ("Utah" or "UT").
   - Optional: `"send_email": false` skips the email with the temporary password.

2. Invoke the function:

   ```powershell
   aws lambda invoke --function-name <CreateStaffFunctionName> --payload fileb://staff.json out.json
   Get-Content out.json
   ```

   Success looks like `{"created": true, ...}`. A failure returns `{"created": false, "error": "..."}`
   and keeps nothing.

3. Cognito emails the person a temporary password. On their first login to the city app, they must
   choose a new password.
