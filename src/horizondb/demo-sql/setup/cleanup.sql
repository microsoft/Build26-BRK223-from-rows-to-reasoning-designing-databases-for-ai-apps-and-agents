DELETE FROM ai.pipelines WHERE name = 'product_rag_pipeline_build_2026';
DROP TABLE IF EXISTS product_rag_pipeline_build_2026_output CASCADE;

-- Clean up pipeline (removes triggers, checkpoints, and run history)
SELECT ai.drop('product_rag_pipeline_build_2026');

DELETE FROM product_sample
WHERE title = 'New Chair for Living Room';

-- Clean up Graph
SELECT ai.drop('style_tagger');

DELETE FROM style_tagger_output
WHERE title = 'New Chair for Living Room';



