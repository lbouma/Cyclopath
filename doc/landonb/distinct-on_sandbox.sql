

CREATE TEMPORARY TABLE breakfast (
   whom TEXT,
   bread TEXT,
   juice TEXT,
   dairy TEXT,
   coffee TEXT,
   tea TEXT,
   spam TEXT);

INSERT INTO breakfast
     (whom,    bread,       juice,        dairy,  coffee,  tea,    spam)
VALUES
     ('april', 'spam',      'spam',       'spam', 'spam',  'spam', 'spam')
   , ('brita', 'roll',      'orange',     'tofu', 'black', 'grey', 'spam')
   , ('carla', 'muffin',    'orange',     'eggs', 'cream', 'herb', NULL)
   , ('davis', 'bagel',     'grapefruit', 'eggs', 'black', 'herb', NULL)
   , ('ebert', 'croissant',  NULL,        'eggs', 'black', 'grey', 'spam')
   , ('ebert', 'croissant',  NULL,        'eggs', 'black', 'grey', 'spam')
   ;

SELECT                      * FROM breakfast ORDER BY whom;
-- With DISTINCT ON, ORDER BY must match... so after the match, the order by
-- determines which matching row is the one that gets selected.
SELECT DISTINCT ON (bread)  * FROM breakfast ORDER BY bread, whom;
SELECT DISTINCT ON (juice)  * FROM breakfast ORDER BY juice, whom;
SELECT DISTINCT ON (dairy)  * FROM breakfast ORDER BY dairy, whom;
SELECT DISTINCT ON (coffee) * FROM breakfast ORDER BY coffee, whom;
SELECT DISTINCT ON (tea)    * FROM breakfast ORDER BY tea, whom;
SELECT DISTINCT ON (spam)   * FROM breakfast ORDER BY spam, whom;

SELECT DISTINCT ON (dairy, coffee) * FROM breakfast ORDER BY dairy, coffee, whom DESC;
--

-- 3 rows:
SELECT DISTINCT ON (dairy) dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
-- same 4 rows:
SELECT DISTINCT (dairy) dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
SELECT DISTINCT ON (dairy, coffee) dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
SELECT DISTINCT dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
-- heh?:
SELECT (dairy) dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
SELECT dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
-- implicit 'as'!:
SELECT (coffee) dairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
SELECT (coffee, dairy) coffeedairy, coffee FROM breakfast ORDER BY dairy, coffee DESC;
-- incorrect (dairy cannot be in order by):
--  SELECT DISTINCT (coffee, dairy) coffeedairy, coffee FROM breakfast ORDER BY coffee, dairy DESC;
SELECT DISTINCT (coffee, dairy) coffeedairy, coffee, dairy FROM breakfast ORDER BY coffee, dairy DESC;
-- incorrent (missing group-by dairy):
--  SELECT DISTINCT (coffee, dairy) coffeedairy, coffee, dairy FROM breakfast GROUP BY coffee;
SELECT DISTINCT (coffee, dairy) coffeedairy, coffee, dairy FROM breakfast GROUP BY coffee, dairy;
SELECT DISTINCT (coffee, dairy) coffeedairy, coffee FROM breakfast ORDER BY coffee DESC;
-- incorrect (coffeedairy is not a column):
--  SELECT DISTINCT ON (coffee, dairy) coffeedairy, coffee FROM breakfast ORDER BY coffee, dairy DESC;
SELECT DISTINCT ON (coffee, dairy) dairy, coffee FROM breakfast ORDER BY coffee, dairy DESC;

SELECT DISTINCT ON (coffee) coffee, dairy FROM breakfast GROUP BY coffee, dairy;


SELECT DISTINCT * FROM breakfast GROUP BY bread, whom, juice, dairy, coffee, tea, spam ORDER BY dairy, coffee, whom DESC;
SELECT DISTINCT * FROM breakfast GROUP BY dairy, coffee, bread, whom, juice, tea, spam ORDER BY dairy, coffee, whom DESC;
SELECT DISTINCT dairy, coffee, bread, whom, juice, tea, spam FROM breakfast GROUP BY dairy, coffee;
SELECT dairy, coffee, FIRST(bread), FIRST(whom), FIRST(juice), FIRST(tea), FIRST(spam) FROM breakfast GROUP BY dairy, coffee;




create temp table eggs (spam TEXT PRIMARY KEY);
ccpv3=> insert into eggs (spam) values ('a'),('a');
ERROR:  duplicate key value violates unique constraint "eggs_pkey"

DROP FUNCTION testt();
CREATE FUNCTION testt()
   RETURNS VOID AS $$
   BEGIN
      insert into eggs (spam) values ('a'),('a');
   EXCEPTION WHEN unique_violation THEN
      RAISE INFO 'ha';
   END;
$$ LANGUAGE plpgsql VOLATILE;
select testt();


