# l2met

Convert a formatted log stream into metrics.

* [Current Release](#current-release)
* [Synopsis](#synopsis)
* [Features](#features)
* [Log Conventions](#log-conventions)
* [Getting Started](#getting-started)
* [Hacking on l2met](#hacking-on-l2met)

## Current Release

* Tip: [v2.0beta](https://github.com/ryandotsmith/l2met/tree/v2.0beta)
* Stable: [v0.11](https://github.com/ryandotsmith/l2met/tree/v0.11)

## Synopsis

L2met receives HTTP requests that contain a body of rfc5424 formatted data. Commonly data is drained into l2met by [logplex](https://github.com/heroku/logplex) or [log-shuttle](https://github.com/ryandotsmith/log-shuttle).

Once data is delivered, l2met extracts and parses the individual log lines using the [log conventions](#log-conventions) and then stores the data in redis so that outlets can read the data and build metrics. The librato_outlet is the most popular and will put all of your metrics into your librato account. See the [setup](#setup) section to get started.

## Log Conventions

L2met uses convention over configuration to build metrics. Keys that are prefixed with measre and have numerical values will be analyzed. L2met uses a loosely defined key=val log structure.

### Keywords:

There are only a few keywords that l2met will parse.

* measure.*
* source

Any key that begins with measure. will be considered for a measurement. You can add a source key to further identify the measurement.

A simple example:

```ruby
$stdout.puts("measure.db.latency=20")
```

Metrics Produced:

* db.latency.min
* db.latency.median
* db.latency.perc95
* db.latency.perc99
* db.latency.max
* db.latency.mean
* db.latency.last
* db.latency.count
* db.latency.sum

An example using [multi-metrics](#multi-metrics) and a source key.

```ruby
$stdout.puts("source=prod measure.db.latency=20 measure.view.latency=10")
```

Metrics Produced:

* prod.db.latency.min
* prod.db.latency.median
* prod.db.latency.perc95
* prod.db.latency.perc99
* prod.db.latency.max
* prod.db.latency.mean
* prod.db.latency.last
* prod.db.latency.count
* prod.db.latency.sum
* prod.view.latency.min
* prod.view.latency.median
* prod.view.latency.perc95
* prod.view.latency.perc99
* prod.view.latency.max
* prod.view.latency.mean
* prod.view.latency.last
* prod.view.latency.count
* prod.view.latency.sum

## Features

* [High resolution buckets](#high-resolution-buckets)
* [Drain Prefix](#drain-prefix)
* [Multi-metrics](#multi-metrics)
* [Heroku Router](#heroku-router)
* [Bucket attrs](#bucket-attrs)
* [HTTP Outlet](#http-outlet)
* Librato Outlet
* Graphite Outlet

### Multi-metrics

We want to be able to specify multiple measurements on a single line so as not to have to pay the (albeit low) overhead of writing to stdout. However, we don't want to take every k=v under the sun. L2met has always forced you to think about the things your are measuring and this feature does not regress in that regard.

Example:

```
echo 'measure=hello val=10 measure.world=10' | log-shuttle
```

This will result in 2 buckets:

1. {name=hello, vals=[10], ...}
2. {name=world, vals=[10], ...}

Thus you can measure multiple things provided the key is prefixed with `measure.`.

### Heroku Router

The Heroku router has a log line convention described [here](https://devcenter.heroku.com/articles/http-routing#heroku-router-log-format)

This feature will read the User field in the syslog packet looking for the string "router." If a match is had, we will parse the structured data and massage it to match the l2met convention. Furthermore, we will prefix the measurement name with the parsed host field in the log line.

Example:

```
path=/logs host=test.l2met.net connect=1ms service=2ms bytes=0
```

Would produce the following buckets:

1. {name=router.connect source=test.l2met.net.connect vals=[1]}
2. {name=router.service source=test.l2met.net.service vals=[2]}
3. {name=router.bytes   source=test.l2met.net.bytes   vals=[0]}

### Drain Parameters

There are several configuration options that can be specified at the drain level. These options will be applied to all of the metrics coming into the drain.

* Resolution
* Prefix

#### High Resolution Buckets

By default, l2met will hold measurements in 1 minute buckets. This means that data visible in librato and graphite have a granularity of 1 minute. However, It is possible to to achieve a greater level of resolution. For example, you can get 1 second level resolution by appending a query parameter to your drain url. Notice that the resolution is specified in seconds.

The supported resolutions are: 1, 5, 30, 60.

Drain URL:

```
https://user:token@l2met.herokuapp.com/logs?resolution=1
```

#### Drain Prefix

It can be useful to prepend a string to all metrics going into a drain. For instance, say you want all of your pretrics to include the environment or app name. You can acheive this by adding a drain prefix.

Drain URL:

```
https://token@l2met.herokuapp.com/logs?prefix=myapp.staging
```

### Bucket Attrs

Most outlet providers allow meta-data to be associated with measurements. Bucket attrs is the l2met feature that allows you to interact with this meta-data.

#### Units

L2met supports associating units with numbers by appending on a non-digit sequence after the digits. L2met will assign all measurements a units of *y* unless specified. You can specify a unit by prepending `/[a-zA-z]+/` after the digit. For instance:

```
measure.db.get=1ms measure.web.get=1
```

This will create the following buckets:

1. {name="measure.db.get", vals=[1], units="ms"}
2. {name="measure.web.get", vals=[1], units="y"}

#### Min Y Value

Librato charts allow charts to have a min y value. L2met sets this to 0. It cant not be overriden at this time. Open a GH issue if this is a problem for you.

### HTTP Outlet

The HTTP Outlet is a read API for your metrics. You can query metrics by id. Id construction is a bit rough at this stage, but if you know what you are looking for, reading metrics can be quite simple. For example, if the following logs are emmited

```
measure.db.get=10ms
```

The metrics can be accessed by the following request:

```bash
$ curl http://your-token@l2met.net/metrics?name=db.get&resolution=60&units=ms&limit=1&offset=1
```

Depending on the resolution of the drain, you will get the last bucket offset by one. The offset implies that you are reading the previous bucket with respect to time. For instance, if your resolution is 60 (1 minute) then an offset of 1 will produce the last minute's bucket.

#### Metric Assertion

You can also assert what you expect the metrics to be. This is useful in that you can point pingdom directly at your l2met instance and create alerts on metrics. For example, if an alert must be made when user signups fall below 5 per minute, we could construct the following request:

```bash
$ curl http://your-token@l2met.net/metrics?name=db.get&resolution=60&units=ms&limit=1&offset=1&count=5
```

If there were only 4 counts of user.signup, then the query would return a 404 which would cause pingdom to send the alert.

The following metrics can be asserted:

* count
* mean
* sum

Tolerance can also be applied to all of the assertions. This compensates for the lack of in-equality operators in the URL. If the tolerance is not present, it is assumed to be 0. If the tolerance is specified, it applies to all metric assertions. You must construct separate requests if you want unique tolerance to metric assertions.

For example, If we wanted to test if the count was 5 +/- 2, the following request would suffice:

```bash
$ curl http://your-token@l2met.net/metrics?name=db.get&resolution=60&units=ms&limit=1&offset=1&count=5&tol=2
```

## Getting Started

The easiest way to get l2met up and running is to deploy to Heroku. This guide assume you have already created a Heroku & Librato account.

#### Create a Heroku app.

There is a setup command that will take care of creating the Heroku app and setting up l2met. The command takes 3 arguments:

1. The name of the newly created l2met heroku app.
2. The email address of your Librato account.
3. The API token of your Librato account.

You can find your Librato account details [here](https://metrics.librato.com/account#api_tokens).

```bash
$ curl https://s3-us-west-2.amazonaws.com/l2met/v2.0beta/linux/amd64/l2met.tar.gz | tar xvz
$ ./setup my-l2met my-librato-email@domain.com my-librato-token
```

#### Sending data to l2met

Now that you have created an l2met app, you can drain logs from other heroku apps into your newly created l2met Heroku app.

After running the setup command, the last line provided a drain url. We can add that drain url to a heroku app. For example, if the drain url provided by the setup command was: `https://ZW1haWw6dG9rZW4=@l2met.herokuapp.com/logs` and we wich to drain logs from `my-app` into l2met, we can run the following command:

```bash
$ heroku drains:add https://ZW1haWw6dG9rZW4=@l2met.herokuapp.com/logs -a myapp
```

## Hacking on l2met

Before working on a new feature, send your proposal to the [mailing list](https://groups.google.com/d/forum/l2met) for tips & feedback. Be sure to work on a feature branch and submit a PR when ready.

[![Build Status](https://drone.io/github.com/ryandotsmith/l2met/status.png)](https://drone.io/github.com/ryandotsmith/l2met/latest)

```bash
$ go version
go version go1.0.3
$ ./redis-server --version
Redis server v=2.6.7 sha=00000000:0 malloc=libc bits=64
```

```bash
$ git clone git://github.com/ryandotsmith/l2met.git
$ cd l2met
$ export SECRETS=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | openssl base64)
$ export REDIS_URL=redis://localhost:6379
$ redis-server &
$ go test ./...
```
