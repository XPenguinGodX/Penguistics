// The same user pool and app client as the civilian app: staff and civilians are
// one pool, told apart by the CityStaff group. Values are the stack outputs
// UserPoolId and UserPoolClientId; update both apps together if they ever change.
const amplifyconfig = '''{
  "UserAgent": "aws-amplify-cli/2.0",
  "Version": "1.0",
  "auth": {
    "plugins": {
      "awsCognitoAuthPlugin": {
        "UserAgent": "aws-amplify-cli/0.1.0",
        "Version": "0.1.0",
        "CognitoUserPool": {
          "Default": {
            "PoolId": "us-east-1_hBU4IWTJa",
            "AppClientId": "4mrf19b84j4itamenual7qmll3",
            "Region": "us-east-1"
          }
        },
        "Auth": {
          "Default": {
            "authenticationFlowType": "USER_SRP_AUTH",
            "passwordProtectionSettings": {
              "passwordPolicyMinLength": 8,
              "passwordPolicyCharacters": [
                "REQUIRES_LOWERCASE",
                "REQUIRES_UPPERCASE",
                "REQUIRES_NUMBERS",
                "REQUIRES_SYMBOLS"
              ]
            }
          }
        }
      }
    }
  }
}''';
