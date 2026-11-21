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

## City website hosting (#22)

`Hosting/city.yaml` creates a separate `penguistics-city` CloudFormation stack:
a private, encrypted S3 bucket and a CloudFront distribution at
`https://city.penguistics.com`. Only this distribution can read the bucket.
HTTP redirects to HTTPS, and 403/404 responses fall back to `index.html` for SPA
navigation. The public website serves the login screen; Cognito and API city
authorization still protect report data.

Deploy in this order, after reviewing and approving the AWS changes:

1. Deploy the backend's CORS update using the existing SAM build/deploy workflow
   from `Backend`. Allowed origins are the city and civilian sites (including
   `www`) and local development ports 5000 and 5001. Random Flutter ports are no
   longer allowed. CORS is a browser rule, not a replacement for authentication.
2. From the repository root, read the existing certificate and deploy hosting:

   ```powershell
   $certificateArn = aws cloudformation describe-stacks --stack-name penguistics --region us-east-1 --query "Stacks[0].Outputs[?OutputKey=='SharedCertificateArn'].OutputValue" --output text
   aws cloudformation deploy --template-file Hosting/city.yaml --stack-name penguistics-city --region us-east-1 --parameter-overrides "CertificateArn=$certificateArn"
   ```

3. Read the hosting outputs:

   ```powershell
   aws cloudformation describe-stacks --stack-name penguistics-city --region us-east-1 --query "Stacks[0].Outputs" --output table
   ```

4. Build the city app from its directory, using the permanent API address:

   ```powershell
   cd Frontend-City/penguincity
   flutter build web --release --dart-define=PEN_API=https://api.penguistics.com
   ```

5. From that same app directory, upload to the `CityBucketName` output and
   invalidate the `CityDistributionId` output. Replace the placeholders with
   the output values:

   ```powershell
   powershell -File ../../Hosting/publish-city.ps1 -BucketName <CityBucketName> -DistributionId <CityDistributionId>
   ```

   Check each command succeeds before continuing. Uploads keep previous assets
   so an already-open browser can finish loading its version. `no-cache` asks
   browsers and CloudFront to revalidate assets; invalidation clears existing
   cached responses. The script uploads JavaScript modules (`.mjs`) with
   `application/javascript` and WebAssembly (`.wasm`) with `application/wasm`.
   This prevents browser MIME errors that can leave Amplify login loading.
   Repeat the build and publishing script for subsequent releases.
6. In Namecheap Advanced DNS, add CNAME Host `city`, Value the full `CityDnsTarget`
   CloudFront hostname, TTL Automatic. Use no `https://` prefix or path. Preserve
   the existing `api` and certificate-validation records.
7. Once the distribution is deployed and DNS propagates, open
   `https://city.penguistics.com` in Edge. Verify staff login, map, report details,
   photo loading, and status actions. Refresh the page to confirm routing works.
   Direct unauthenticated requests to the S3 bucket should return 403.

The hosting bucket is retained on stack deletion to protect app artifacts; remove
it separately if no longer needed. The distribution is deleted with the hosting
stack. Deleting the backend still removes its API and accounts, so the website
cannot function until those are restored. Use the existing shared certificate;
do not request another one for the city site.

## Civilian website hosting (#23)

`Hosting/civilian.yaml` deploys the independent `penguistics-civilian` stack.
It uses the same private S3, CloudFront Origin Access Control, HTTPS, and SPA
fallback setup as the city app. One distribution serves both `penguistics.com`
and `www.penguistics.com`, using the existing root/wildcard certificate in
us-east-1. Both names serve the app directly; there is no redirect between them.
Browser login sessions are separate for each origin.

After approval, deploy from the repository root:

```powershell
$certificateArn = aws cloudformation describe-stacks --stack-name penguistics --region us-east-1 --query "Stacks[0].Outputs[?OutputKey=='SharedCertificateArn'].OutputValue" --output text
aws cloudformation deploy --template-file Hosting/civilian.yaml --stack-name penguistics-civilian --region us-east-1 --parameter-overrides "CertificateArn=$certificateArn"
aws cloudformation describe-stacks --stack-name penguistics-civilian --region us-east-1 --query "Stacks[0].Outputs" --output table
```

Build from `Frontend-Civilian/penguinspotter` with both required defines:

```powershell
flutter build web --release --dart-define=PEN_API=https://api.penguistics.com --dart-define=SIGNUP_CANCEL_URL=https://api.penguistics.com/signup/cancel
```

From that same app directory, substitute `CivilianBucketName` and
`CivilianDistributionId` from the stack outputs:

```powershell
powershell -File ../../Hosting/publish-civilian.ps1 -BucketName <CivilianBucketName> -DistributionId <CivilianDistributionId>
```

The script performs S3 sync, explicitly uploads `.mjs` as JavaScript and `.wasm`
as WebAssembly, and invalidates CloudFront. This includes the Amplify worker MIME
fix discovered during city hosting. It preserves old assets and uses `no-cache`
for revalidation. Repeat build and publish for subsequent releases.

In Namecheap Advanced DNS, use the `CivilianDnsTarget` output as the Value for:

| Type | Host | Value | TTL |
| --- | --- | --- | --- |
| ALIAS Record | @ | CivilianDnsTarget hostname | Automatic |
| CNAME Record | www | CivilianDnsTarget hostname | Automatic |

Use hostnames without `https://` or a path. Inspect existing root/www records and
replace conflicting parking, redirect, A, AAAA, ALIAS, or CNAME records only;
preserve MX/TXT email records and the `api`, `city`, and ACM validation records.
If an existing root website is in use, coordinate its replacement before saving.

Both HTTPS origins are already in API CORS and the photo bucket's read rules.
After DNS propagation, test root and www in Edge, then test on a phone browser:
sign up and email confirmation, login, location permission, choosing/taking a
photo, report submission, My Reports, and page refresh. Verify uploads and
sign-up cancellation reach the permanent API. Direct unsigned S3 access must
remain blocked. Report status refresh on the civilian map is tracked separately
in #28.

As with city hosting, the artifact bucket is retained on stack deletion, while
the distribution is deleted. Phone and native builds continue using the same
application source; these resources host only the web build.

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
