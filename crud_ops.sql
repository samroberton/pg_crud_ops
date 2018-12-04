--
-- Generic CRUD mechanics
--


create schema crud_ops;


/*
 * When we pull args out of a `jsonb` structure, we get a `jsonb` value, and if
 * we want to call `get_user(username)`, we need an overload which will accept
 * `jsonb`. Getting a `text` from `jsonb` is unfortunately annoying.
 */
create function crud_ops.json2text(from_json jsonb)
    returns text as $$
  select from_json #>> '{}';
$$ language sql;


comment on function crud_ops.json2text is 'Convert a `jsonb` value which is a JSON string to `text`.';



/*
 * Given a JSONB map of arguments, use the keys to produce a string of
 * named-parameter function arguments mapped to a lookup of that argument in
 * `$1`.  (Ignores the values provided in the map.)
 *
 *     select crud_ops.format_crud_args('{"username":"sam","school-code":"af.sydney"}');
 *
 * results in the text
 *
 *     username => $1->'username', "school-code" => $1->'school-code'
 */
create function crud_ops.format_crud_args(args jsonb)
    returns text
as $$
declare
    arg record;
    arg_names text[] = '{}';
    the_result text;
begin
    for arg in select * from pg_catalog.jsonb_each(args)
    loop
        arg_names := arg_names || array[(pg_catalog.quote_ident(arg.key) || ' => $1->' || pg_catalog.quote_literal(arg.key))];
    end loop;

    return pg_catalog.array_to_string(arg_names, ', ');
end
$$ language plpgsql;


comment on function crud_ops.format_crud_args is '`jsonb` JSON object -> function arglist using object''s keys as named parameters (ignoring values).';



/*
 * Invoke a single API function in the given schema.
 *
 *     select crud_ops.single_crud_op("api", "get_user", '{"username":"sam"}');
 * is equivalent to:
 *     select to_jsonb(api.get_user(username => 'sam'));
 */
create function crud_ops.single_crud_op("schema" text, "api" text, args jsonb)
    returns jsonb
as $$
declare
    sql_string text;
    crud_op_result record;
begin
    sql_string := pg_catalog.format( 'select to_jsonb(%I.%I(' || crud_ops.format_crud_args(single_crud_op.args) || ')) as the_result'
                                   , single_crud_op."schema"
                                   , single_crud_op."api"
                                   );
    execute sql_string using single_crud_op.args into crud_op_result;
    return crud_op_result.the_result;
end
$$ language plpgsql;


comment on function crud_ops.single_crud_op is 'Invoke <schema>.<api>(...) with `args` exploded to named parameters.';



/*
 * Invoke multiple API functions in the given schema.  `crud-json` is a JSONB
 * array (to allow the caller to define an order of operations).  Each array
 * element is a map, which may have one or more keys.  The key in the map is an
 * arbitrary name for the operation, and the value is a (single-key,
 * single-value) map from API function name to map of arguments. The result is a
 * single map, with the result of each function call under the (arbitrary) name
 * it was given.
 *
 *     crud_ops.crud( "api"
 *                  , '[ {"user":   {"get_user": {"username":"sam"}},
 *                        "school": {"get_school": {"school-code":"af.sydney"}}}
 *                     , {"school_levels": {"get_school_levels":{}}}
 *                     ]'
 *                  )
 *
 * is equivalent to:
 *
 *     jsonb_build_object("user",          to_jsonb(api.get_user(username => 'sam')),
 *                        "school",        to_jsonb(api.get_school("school-code" => 'af.sydney'))
 *                        "school_levels", to_jsonb(api.get_school_levels()));
 */
create function crud_ops.crud("schema" text, "crud-json" jsonb)
    returns jsonb
as $$
declare
    result_json jsonb := '{}';
    crud_map jsonb;
    crud_op record;
    crud_op_result_name text;
    crud_op_details record;
    crud_op_api text;
    crud_op_args jsonb;
    crud_op_result jsonb;
begin
    /* Outermost value is a JSON array of JSON maps. */
    for crud_map in select * from pg_catalog.jsonb_array_elements(crud."crud-json")
    loop
        /* Each map has a key which names the result, and a map describing the operation. */
        for crud_op in select * from pg_catalog.jsonb_each(crud_map)
        loop
            crud_op_result_name := crud_op.key;
            /* The map describing the operation only has one key (the API function name), and a map of args as the value. */
            for crud_op_details in select * from pg_catalog.jsonb_each(crud_op.value)
            loop
                crud_op_api := crud_op_details.key;
                crud_op_args := crud_op_details.value;
                crud_op_result := pg_catalog.to_jsonb(crud_ops.single_crud_op(crud."schema", crud_op_api, crud_op_args));
                result_json := result_json || pg_catalog.jsonb_build_object(crud_op_result_name, crud_op_result);
            end loop;
        end loop;
    end loop;
    return result_json;
end
$$ language plpgsql;


comment on function crud_ops.crud is 'Repeatedly invoke `crud_ops.single_crud_op` for a sequence of "api -> crud-op args" JSON objects, merging results.';
