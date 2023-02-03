---
title: DDNS with Raspberry Pi, Part 2!
date: 2023/2/3
description: A quick and dirty way to set up your own self-hosted, *actual* Dynamic DNS service.
tag: raspi,raspberry-pi,dns,aws,lambda
author: Dmitriy
---

# DDNS with Raspberry Pi, Part 2!

In the initial article [Free-ish Dynamic DNS with AWS Lambda and a Raspberry Pi](http://loshakov.link/blog/pidns), we discussed how to set up a rudimentary Dynamic-DNS-like service using AWS Lambda and a Raspberry Pi. In this article, I'm following up with a strategy (and some Terraform!) for how to implement *actual* Dynamic DNS.

## Brief Overview of Architecture

If you haven't read the initial article, it has a lot of great context and details for how we originally set this up, but I will summarize some of it here for convenience and brevity.

We started with AWS Lambda, where we created a Lambda function that is little more than a "hello world" that takes a map of values as input and prints out one of the keys in that map, generating a log entry in CloudWatch when it is run. We're then able to invoke this Lambda from a Raspberry Pi, with the Raspberry Pi contacting an IP-lookup service to provide us with our WAN (Internet-facing) IP address, and then piping that value into a Lambda invocation, invoking the function we created earlier. The end result is that we now have a CloudWatch Log entry containing our external IP address, which we can look up at any time to see what our home IP address is.

This is fantastically simple and should genuinely operate in AWS Free Tier, but a big part of the appeal of Dynamic DNS is the convenience and polish of it, so lets build on what we created earlier.

### Our Lambda

This time around, we're going to create a Lambda that actually does some useful work, instead of just generating a log output.

We can use AWS Lambda functions to reach various AWS services using AWS APIs via whatever vehicle we choose. In this case, I chose to use Python for the Lambda function language since I'm familiar with AWS' boto3 Python library. We're going to use the Route53 API client to change a record in one of our hosted zones.

The final Lambda code will look something like the below:

```
import boto3
import os


session = boto3.session.Session()
r53_cli = session.client('route53')

HOSTED_ZONE_ID = os.environ['HOSTED_ZONE_ID']
SERVER_PREFIX = os.environ['SERVER_PREFIX']
DOMAIN_NAME = os.environ['DOMAIN_NAME']


def lambda_handler(event, context):
    latest_ip = event['ip']

    response = r53_cli.change_resource_record_sets(
        HostedZoneId=HOSTED_ZONE_ID,
        ChangeBatch={
            'Changes': [
                {
                    'Action': 'UPSERT',
                    'ResourceRecordSet': {
                        'Name': f"{SERVER_PREFIX}.{DOMAIN_NAME}",
                        'Type': 'A',
                        'ResourceRecords': [
                            {
                                'Value': latest_ip
                            },
                        ],
                        'TTL': 60,
                    },
                },
            ],
        }
    )

    # Should return 'PENDING'
    return response.get('ChangeInfo', {}).get('Status', 'EMPTY')
```

On a very high level, we are doing the following, in order:
* Instantiating our API client (for Route53)
* Pulling in some configuration from the environment (this can be stored as you see fit, pulled from SSM, etc)
* Defining our lambda function entrypoint, which does the following:
    * Grabs our IP value from the Lambda invocation
    * Performs a ChangeResourceRecordSets API call to Route53, doing an `UPSERT` which creates or updates a DNS 'A' record located in HOSTED_ZONE, whose name is defined by SERVER_PREFIX and DOMAIN_NAME

I left TTL hard-coded, but it can either be made configurable, or grabbed from the existing DNS record, assuming one exists.

### Our Rapsberry Pi

On the Raspberry Pi side, our configuration is going to be identical:

* Install and configure awscli
* Create a crontab entry that looks like this:

```
5 0 * * * aws lambda invoke --function-name my-function-name --payload {\"ip\":\"$(curl icanhazip.com)\"} /path/to/result/file
```

* `my-function-name` is whatever you choose to name the function, just as before
* `/path/to/result/file` is a required path to output the result of the function invocation

This way, instead of just recording the IP value that we send, we're actually using it to update a DNS record! Voilà, Dynamic DNS!

## Not that free, unfortunately

You'll need an actual domain name for this to work, so depending on what domain registrar you chose, what Top Level Domain you chose, and the actual cost to you of your domain name, this will be a consideration. AWS incurs a base charge for each Route53 Hosted Zone that you maintain as well, so in addition to buying and operating a Raspberry Pi (which *should* be trivial) and owning a domain name, you'll have to pony up $0.50/month for one R53 Hosted Zone.

This still very likely pales in comparison to charges you may incur with popular DDNS services. For example, for me to operate all of this through AWS (domain registered with AWS' Registrar), the monthly cost works out to be around $0.91, which I consider pretty trivial, and then of course I can use that domain name and hosted zone for other purposes.

# Taking it further

Of course there's usually ways to improve on a given solution, and if your router supports DynamicDNS along with a custom script, you may be able to skip the Raspberry Pi altogether.

# Terraform

Before I forget, I've also come up with a [small Terraform module](https://github.com/nijine/lambda-dynamic-dns) that makes it nearly effortless to stand up the AWS Lambda infrastructure. I'll defer to the README for details on how it is implemented.