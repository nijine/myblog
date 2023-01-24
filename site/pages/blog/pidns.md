---
title: Free-ish Dynamic DNS with AWS Lambda and a Raspberry Pi
date: 2023/1/24
description: A quick and dirty way to set up your own self-hosted Dynamic DNS service.
tag: raspi,raspberry-pi,dns,aws,lambda
author: Dmitriy
---

# Free-ish Dynamic DNS with AWS Lambda and a Raspberry Pi

If you've ever wondered how you might go about setting up Dynamic DNS without paying for something like dyndns.org, and you don't have a router with this functionality handy (but you *do* have a Raspberry Pi), this is your guide! If you're wondering why the title states "Free-ish" and not "Free," it's because there are a couple ways of going about this, and at a bare minimum, you'll incur the cost of keeping a Raspberry Pi plugged in and operating (and also acquiring one, if you don't already own one).

## Background

The need for this actually spawned while I was packing for a trip, and I had just set up a PiKVM connected to one of my home machines. While your WAN IP doesn't usually change terribly often, I figured it would be easy enough to set up a make-shift solution to the problem of figuring out my home network WAN IP.

## Setup

The basic gist of the setup is a Raspberry Pi connected to power and Wi-Fi, with a script running as a cron job every hour that collects my current WAN IP and invokes a Lambda function to record the current value.

In this basic iteration, all I have to do to read the value is open up the CloudWatch logs for my Lambda and check what the last value is.

This is far from elegant, but it's the kind of thing that can be thrown together in a matter of minutes if you happen to find yourself in the same pinch that I found myself in. The next few sections cover the basic needs and setup.

### Raspberry Pi

This can be literally any Raspberry Pi that you can provide with a power and network connection. As long as it runs a full operating system (and is a not a microcontroller variant of a Raspberry Pi, i.e. RP2040), you're good to go. There are a variety of operting systems out there to choose from, but you can easily grab Raspbian and set it up to pre-enable SSH and pre-connect to your Wi-Fi network, if applicable.

### AWS & Lambda

This is the one that may take a few extra minutes if you don't already have an account with [AWS](https://aws.com). You'll need to create an account and configure at least one IAM user, so that we can generate an API key for that user and load it onto the Raspberry Pi for invoking the Lambda function later on.

Lambda is the specific product we're going to use. It is AWS' server-less service for running everything from basic scripts to larger applications. We're also going to be using CloudWatch, which is AWS' monitoring and log aggregation service. It's technically not the star of the show, but for our very basic implementation, we're going to use CloudWatch Logs to store our WAN IP value.

## Putting it all together

### AWS

Note: The following assumes that you have a working AWS account and have set up an IAM user.

We'll want to start off by creating the Lambda that is going to be invoked. From the console home page, navigate over to the AWS Lambda dashboard and click "Create Function" at the top right. You'll be greeted with a "Create function" page, which should present you with three options: Author from scratch, Use a blueprint, and Container image. We're going to select "Use a blueprint" since it's the fastest way to get up and running, and since we don't need anything other than the very basics here.

Under "Select blueprint" we can leave the default option of "Hello world function." The "Function name" field can be anything you'd like, keep it simple so it is easy to refer to later on. Runtime and Architecture should be pre-selected, and for "Execution role" we can leave the default "Create a new role with basic Lambda permissions" selected, since we don't need any special permissions here other than the default, which should provide CloudWatch Logs access. We'll see a preview of our Lambda code in a box at the bottom of the window, but we can't make changes until we create the function, so go ahead and click "Create function."

Once the function is created, we're dropped into the management page for our function. "Hello world" is a basic template that does nothing more than dump our Lambda input parameters out to a log, which is all we need. In the "Code source" window, go ahead and remove any extra log lines, since we only need to log one value (i.e. remove `console.log('value2 =', event.key2);` and so on), then click "Deploy" at the top of that window to save your changes.

Our lambda is ready to use!

If you have not yet done so, before leaving the AWS Console, navigate over to IAM and create a user. We're going to need a user that has permissions to run our Lambda. You'll want a policy that looks something like this:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:<your-region>:<your-account-id>:function:<your-function-name>"
        }
    ]
}
```

Once the policy is created and applied (can be attaached directly if you don't feel like managing a separate role and/or policy), go ahead and create an API Access Key (usually found under the "Security Credentials" tab of a given users page). Make note of the ID and Secret values, we'll need these shortly.

### Raspberry Pi

On the Raspberry Pi, we're going to need to do four things: (1) Install awscli, (2) configure awscli, and (3) add a script invoking awscli to our crontab. 

#### AWS Client
This will allow us to invoke our Lambda function from the Raspberry Pi.

If you're running a recent version of Raspbian, you'll want to do something like this:
`sudo apt update && sudo apt install awscli -y`

Otherwise, check out which awscli installation makes sense for your setup [here](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

Once that's done, go ahead and configure awscli:
`aws configure`

You'll go through and enter the API Key ID and Secret from earlier, as well as the region that you're operating in, i.e. "us-east-1" for US East (N. Virginia). You can leave the profile set to the default value (just hit Enter).

Let's go ahead and test out invoking our Lambda to make sure it's working as expected:
`aws lambda invoke --function-name <your-lambda-function-name> --payload '{"key1":"Testing!"}' out`

If all goes well, we should have seen something like this in the output:
```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
```

After a couple of minutes, we should also see something in CloudWatch Logs. Go ahead and navigate to CloudWatch in the AWS console, and then "Logs -> Log groups" along the left-hand navigation panel. We should see a log group with the same name as our function, go ahead and click on the log group name.

If all went well, we should see a log stream in the list with a format similar to this:
`YYYY/MM/DD/[$LATEST]<some-random-uuid>`

Go ahead and click into that log stream, and viola! We should see a log line towards the middle of the log that shows `INFO value1 = Testing!` at the very end. Our Lambda setup is functioning!

NOTE: You may want to go back to the log group page and modify the retention settings, otherwise it *may* eventually incur a cost to keep your logs retained forever, once they accumulate past a certain point. The setting is usually under the "Actions" menu button, under "Edit retention setting." You'll want to set it to something reasonable. I set mine for a day, since I have no use for the historical data.

#### Lambda-invoking Script
Once we've confirmed that invoking our Lambda works, lets add a script to our crontab. If you're not familiar with the crontab, it's basically a built-in piece of automation in most Linux systems that enables you to run tasks on a schedule, such as scripts.

Open up the crontab by running the following:
`crontab -e`

And then at the very bottom, you'll want to add something like this:
`5 0 * * * aws lambda invoke --function-name <my-lambda-function-name> --payload {\"key1\":\"$(curl icanhazip.com)\"} /dev/null`

Then save changes and exit the text editor.

Note: I like to use `icanhazip.com` since it will return just your IP address as a text string, and is handy for scripting. Also, we need to escape the double-quotes to be able to run a command within a command and still have it be inputted as valid JSON to the awscli.

`5 0 * * *` is our schedule, and the rest of the line is our awscli command. This schedule runs at 12:05 UTC every day, if you'd like to adjust it, [crontab.guru](https://crontab.guru) is a great resource for generating schedules.

We're done! Assuming there are no issues with cron, we should now see a log entry pop up in CloudWatch every morning, a minute or two after 12:05 UTC.

## Taking it further

Of course the above method is very rudimentary, and works fine if you're in a pinch and have to set things up quickly. However, since we're using Lambda anyway, we can write a Lambda function that updates a DNS entry in something like AWS Route53 (AWS' DNS service). So for example if you have a domain name and/or a DNS Hosted Zone in Route53, you can have the Lambda update a DNS record in the hosted zone of your choice. This way, it will behave a lot more like a DynamicDNS service, but this is the part where we go from "Free" to "Free-ish," since owning a domain name will incur a cost, depending on the registrar, top-level domain, etc.

I will likely create a Terraform config with an accompanying Lambda script as a follow-up to the above.
