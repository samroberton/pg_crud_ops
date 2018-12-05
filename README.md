[![CircleCI](https://circleci.com/gh/samroberton/pg_crud_ops.svg?style=svg)](https://circleci.com/gh/samroberton/pg_crud_ops)


# What's this for?

Single-page apps and mobile apps often want to be able to request multiple
"things" of the server in a single network request.

You normally achieve that by abusing the hell out of RESTful-looking resources.
But that makes people angry, and honestly, why make things look RESTful when you
often really want RPC-like semantics anyway?

GraphQL does it a bit more elegantly, but then you have to have resolvers, and
it's built around the idea that the caller should be able to specify any
arbitrary variant of some maximal response payload that it likes.  Most apps
don't need that.

So I think that what you really want is a way to describe a "server-side" API
which consists of (very) small units of RPC-like functionality.  And the client
should be able to request whatever combination of those small units it wants, in
a single network request.

> Why did you put "server-side" in quotes?

Because I also think that mostly, a well-designed product should normally have a
"server-side" whose job is basically to query and update data a relational
database.  Most apps are CRUD apps.

Of course, you need to get that relational data to and from your client-side
app, which wants JSON, so you have to have an ORM in there somewhere.  But I
think that PostgreSQL's JSON support is good enough for Postgres to be your ORM.
So I don't think you need a real "server-side" at all: just give the request
JSON straight to Postgres, and let it do what it's good at.

(Of course, you can't do without a server-side entirely: Postgres isn't going to
be hosting your HTTP server.  But you can have a very, very small one.  Say, one
single file in a tiny container / EC2 instance.  Or an AWS Lambda function, if
you like.)


# Get to the point!

Ok.  Given this in your DB:

```sql
create schema api;

create type api.product as (
    sku text,
    name text
);

create type api."order" as (
    sku text,
    quantity integer
);


create function api.get_products()
    returns api.product[]
as $$
    select array_agg((sku, name) :: api.product)
      from public.product;
$$ language sql;


create function api.get_orders(customer_id integer)
    returns api."order"[]
as $$
    select array_agg((sku, quantity) :: api."order")
      from public.product_order
     where customer_id = get_orders.customer_id;
$$ language sql;
```

your app should be able to send you this JSON:

```javascript
[{
     "the_products": { "get_products": {} },
     "the_orders":   { "get_orders": { "customer_id": 3 } }
}]
```

meaning:

```sql
select api.get_products();
select api.get_orders(customer_id => 3);
```

And if you do, you should get a response something like:

```json
{
    "the_products": [
        {"sku": "1234", "name": "Product A"},
        {"sku": "5678", "name": "Product B"},
        {"sku": "9012", "name": "Product C"}
    ],
    "the_orders": [
        {"sku": "5678", "quantity": 3}
    ]
}
```

So how do you achieve this satisfying simplicity?

You make your "app layer" a single function which calls:

```sql
select crud_ops.crud("schema" => 'api', "crud-json" => ?)
```

where the parameter is the JSON you got from the client.


# Is it really that simple?

Honestly, not quite.

For the example above, you'd actually also need to define this function, which
takes a `jsonb` argument instead of an `integer`:

```sql
create function api.get_orders(customer_id jsonb)
    returns api."order"[]
as $$
    select api.get_orders(customer_id :: text :: integer);
$$ language sql;
```

... because auto-magically converting parameter types is tempting, but probably
ultimately a not a great idea.

But otherwise, yes, it's that simple.

If you don't believe me, run the below, then run `\i crud_ops.sql`, then try out
the above yourself:

```sql
create table product (
    sku text,
    name text
);

create table product_order (
    sku text,
    quantity integer,
    customer_id integer
);

insert into product
            (sku, name)
     values ('1234', 'Product A'),
            ('5678', 'Product B'),
            ('9012', 'Product C');

insert into product_order
            (sku, quantity, customer_id)
     values ('5678', 3, 3);
```


# But what about authentication?

Yeah, you should probably do that.

So you probably shouldn't have your app layer just call `crud_ops.crud`
directly.  You should probably have it call a function that looks more like
this:

```sql
create function api.crud_with_auth("auth-token" text, "crud-json" jsonb)
    returns jsonb
as $$
    -- This `do_auth` function should probably raise an error if the auth
    -- token is not valid, and should probably also call
    --     `set_config('my_app.username', '...')`
    -- so that functions in your API can call
    --     `current_setting('my_app.username')`
    -- to find out who the currently-logged-in user is.
    perform do_auth(auth_token => crud_with_auth."auth-token");

    select crud_ops.crud( "schema" => 'api'
                        , "crud-json" => crud_with_auth."crud-json"
                        );
$$ language sql;
```


# But surely I can't just allow clients to call arbitrary database functions?!

That way madness and security audit failure lies, no?

The `crud_ops.crud` function takes a `schema` as its first argument.  Define
yourself an "api" schema, and only functions in that schema will be available.
Think of the schema as your API interface.

In fact, if you like, define multiple different schemas for different classes of
requests and different endpoints.  That's what I do -- I have one endpoint that
the student client app can call, in `api_student`, and one that the
teacher/admin app can call, in `api_teacher`, and each has a `crud_with_auth`
function like the above.


# Credits

Inspirations I'm grateful for:

* [PostgREST](http://postgrest.org/en/v5.1/) and
  [PostGraphile](https://github.com/graphile/postgraphile) for demonstrating how
  powerful it is to have your database declare the API you want.
* [Om Next](https://github.com/omcljs/om), for the notion that in a client SPA,
  different bits of the page should be able to specify different data
  requirements they have, and something should aggregate that all together and
  send a single request to the server.  Or, from the opposite perspective, for
  the notion that it's not the server's job to predict what combination of
  information the client is going to present on a single page.
* Rich Hickey's [Spec-ulation](https://www.youtube.com/watch?v=oyLBGkS5ICk)
  keynote, for helping me realise that GraphQL's "hey, let me request any
  variation of the response payload I might possibly ever think of by providing
  a slightly different variation of the request" is in fact much less useful
  than just "hey, there are three variants that people want, how about I give
  each one of them a name?"
