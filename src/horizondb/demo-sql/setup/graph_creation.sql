-- ─── Step 2: Build the graph ────────────────────────────────────────────────
SET search_path = ag_catalog, "$user", public, pgfts;

-- Create graph (drop first if re-running)
SELECT ag_catalog.drop_graph('style_graph', true);
SELECT ag_catalog.create_graph('style_graph');

-- Create one node per distinct style
SELECT * FROM ag_catalog.cypher('style_graph', $$
    CREATE (:Style {name: 'Mid-Century Modern', disp_label: 'Mid-Century Modern'}),
           (:Style {name: 'Industrial', disp_label: 'Industrial'}),
           (:Style {name: 'Scandinavian', disp_label: 'Scandinavian'}),
           (:Style {name: 'Bohemian', disp_label: 'Bohemian'}),
           (:Style {name: 'Farmhouse', disp_label: 'Farmhouse'}),
           (:Style {name: 'Minimalist', disp_label: 'Minimalist'}),
           (:Style {name: 'Modern', disp_label: 'Modern'})
$$) AS (v agtype);

-- Create Product nodes and HAS_STYLE edges from pipeline output
DO $$
DECLARE
    r RECORD;
    safe_title TEXT;
    safe_style TEXT;
BEGIN
    SET search_path = ag_catalog, "$user", public, pgfts;
    FOR r IN SELECT id, title, extracted->>'style' AS style
             FROM style_tagger_output
             WHERE extracted->>'style' IS NOT NULL
    LOOP
        safe_title := replace(replace(r.title, '\', '\\'), '''', '\''');
        safe_title := replace(safe_title, '"', '\"');
        safe_style := replace(r.style, '''', '\''');

        EXECUTE format(
            $ex$SELECT * FROM ag_catalog.cypher('style_graph', $cyp$
                MATCH (s:Style {name: '%s'})
                CREATE (:Product {id: %s, title: '%s', disp_label: '%s'})-[:HAS_STYLE]->(s)
            $cyp$) AS (v ag_catalog.agtype)$ex$,
            safe_style, r.id, safe_title, safe_title
        );
    END LOOP;
END $$;

-- Create Category nodes from distinct categories
DO $$
DECLARE r RECORD; safe_cat TEXT;
BEGIN
    SET search_path = ag_catalog, "$user", public, pgfts;
    FOR r IN SELECT DISTINCT ps.category FROM product_sample ps
             JOIN style_tagger_output sto ON ps.id = sto.id
             WHERE ps.category IS NOT NULL
    LOOP
        safe_cat := replace(r.category, '''', '\''');
        EXECUTE format(
            $ex$SELECT * FROM ag_catalog.cypher('style_graph', $cyp$
                CREATE (:Category {name: '%s', disp_label: '%s'})
            $cyp$) AS (v ag_catalog.agtype)$ex$, safe_cat, safe_cat);
    END LOOP;
END $$;

-- Link products to their categories
DO $$
DECLARE r RECORD; safe_cat TEXT;
BEGIN
    SET search_path = ag_catalog, "$user", public, pgfts;
    FOR r IN SELECT sto.id, ps.category FROM style_tagger_output sto
             JOIN product_sample ps ON ps.id = sto.id
             WHERE ps.category IS NOT NULL
    LOOP
        safe_cat := replace(r.category, '''', '\''');
        EXECUTE format(
            $ex$SELECT * FROM ag_catalog.cypher('style_graph', $cyp$
                MATCH (p:Product {id: %s}), (c:Category {name: '%s'})
                CREATE (p)-[:IN_CATEGORY]->(c)
            $cyp$) AS (v ag_catalog.agtype)$ex$, r.id, safe_cat);
    END LOOP;
END $$;

-- Create SIMILAR_TO edges between styles based on ai.generate output
-- Each product's generated field lists related styles → create edges from its style to those
DO $$
DECLARE
    r RECORD;
    related TEXT;
    safe_style TEXT;
    safe_related TEXT;
BEGIN
    SET search_path = ag_catalog, "$user", public, pgfts;
    FOR r IN SELECT DISTINCT style, related_style FROM (
                 SELECT extracted->>'style' AS style,
                        trim(unnest(string_to_array(generated, ','))) AS related_style
                 FROM style_tagger_output
                 WHERE extracted->>'style' IS NOT NULL
                   AND generated IS NOT NULL
             ) sub
    LOOP
        -- Skip self-references and empty strings
        IF r.related_style = '' OR r.related_style = r.style THEN
            CONTINUE;
        END IF;
        safe_style := replace(r.style, '''', '\''');
        safe_related := replace(r.related_style, '''', '\''');

        -- Create edge if both styles exist (ignore duplicates via MERGE-like check)
        BEGIN
            EXECUTE format(
                $ex$SELECT * FROM ag_catalog.cypher('style_graph', $cyp$
                    MATCH (s1:Style {name: '%s'}), (s2:Style {name: '%s'})
                    WHERE NOT EXISTS ((s1)-[:SIMILAR_TO]->(s2))
                    CREATE (s1)-[:SIMILAR_TO {weight: 1}]->(s2)
                $cyp$) AS (v ag_catalog.agtype)$ex$,
                safe_style, safe_related
            );
        EXCEPTION WHEN OTHERS THEN
            -- skip if styles don't exist or edge already exists
            NULL;
        END;
    END LOOP;
END $$;

-- Verify node/edge counts
SELECT 'Products' AS label, COUNT(*) FROM style_graph."Product"
UNION ALL
SELECT 'Styles', COUNT(*) FROM style_graph."Style"
UNION ALL
SELECT 'Categories', COUNT(*) FROM style_graph."Category"
UNION ALL
SELECT 'HAS_STYLE edges', COUNT(*) FROM style_graph."HAS_STYLE"
UNION ALL
SELECT 'IN_CATEGORY edges', COUNT(*) FROM style_graph."IN_CATEGORY"
UNION ALL
SELECT 'SIMILAR_TO edges', COUNT(*) FROM style_graph."SIMILAR_TO";