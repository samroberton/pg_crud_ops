begin;
select plan(13);


--
-- json2text
--

select results_eq(
    $$select crud_ops.json2text('"foo"'::jsonb)$$,
    $$values ('foo')$$,
    'json2text'
);



--
-- format_crud_args
--

select results_eq(
    $$select crud_ops.format_crud_args('{"username":"user@example.com"}'::jsonb)$$,
    $$values ('username => $1->''username''')$$,
    'format_crud_args: happy days'
);


select results_eq(
    $$select crud_ops.format_crud_args('{"username":"user@example.com","foo":"bar"}'::jsonb)$$,
    $$values ('foo => $1->''foo'', username => $1->''username''')$$,
    'format_crud_args: multiple arguments'
);


select results_eq(
    $$select crud_ops.format_crud_args('{"school-code":"af.sydney"}'::jsonb)$$,
    $$values ('"school-code" => $1->''school-code''')$$,
    'format_crud_args: hyphen in name'
);


select results_eq(
    $$select crud_ops.format_crud_args('{"school code":"af.sydney"}'::jsonb)$$,
    $$values ('"school code" => $1->''school code''')$$,
    'format_crud_args: space in name'
);


select results_eq(
    $$select crud_ops.format_crud_args('{"school \"quoted\" code":"af.sydney"}'::jsonb)$$,
    $$values ('"school ""quoted"" code" => $1->''school "quoted" code''')$$,
    'format_crud_args: double quotes in name'
);


select results_eq(
    $$select crud_ops.format_crud_args('{"school ''quoted'' code":"af.sydney"}'::jsonb)$$,
    $$values ('"school ''quoted'' code" => $1->''school ''''quoted'''' code''')$$,
    'format_crud_args: single quotes in name'
);



--
-- single_crud_op
--

select results_eq(
    $$select crud_ops.single_crud_op('crud_ops', 'json2text', '{"from_json":"foo"}'::jsonb)$$,
    $$values ('"foo"'::jsonb)$$,
    'single_crud_op: call json2text'
);


select throws_ok(
    $$select crud_ops.single_crud_op('crud_ops', 'json2text', '{"not_the_arg_name":"foo"}'::jsonb)$$,
    '42883', -- undefined_function
    null,
    'single_crud_op: wrong argument name'
);


select throws_ok(
    $$select crud_ops.single_crud_op('crud_ops', 'json2text', '{"from_json":"foo","extra_arg":"bar"}'::jsonb)$$,
    '42883', -- undefined_function
    null,
    'single_crud_op: extra argument'
);


--
-- crud
--

select results_eq(
    $$select crud_ops.crud('crud_ops', '[{"foobar":{"json2text":{"from_json":"happy days!"}}}]')$$,
    $$values ('{"foobar": "happy days!"}'::jsonb)$$,
    'crud: call json2text -- happy days'
);


select results_eq(
    $$select crud_ops.crud('crud_ops', '[{"foo":{"json2text":{"from_json":"hello!"}},"bar":{"json2text":{"from_json":"goodbye!"}}}]')$$,
    $$values ('{"foo":"hello!", "bar":"goodbye!"}'::jsonb)$$,
    'crud: call json2text -- two calls in same map'
);


select results_eq(
    $$select crud_ops.crud('crud_ops', ( '[{"foo":{"json2text":{"from_json":"hello!"}},"bar":{"json2text":{"from_json":"goodbye!"}}},'
                                       || '{"baz":{"json2text":{"from_json":"hello again!"}}}]')::jsonb)$$,
    $$values ('{"foo":"hello!", "bar":"goodbye!", "baz":"hello again!"}'::jsonb)$$,
    'crud: call json2text -- two maps in the array'
);


select * from finish();
rollback;
