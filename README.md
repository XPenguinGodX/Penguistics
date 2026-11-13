# Penguistics
A civic pipeline for civilians to report issues on the road, the system will validate the legitimacy of the report, Store it, and display it on the city worker cite with the optimal routes and course of action

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
