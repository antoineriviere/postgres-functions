-- Function: xx_99_utils.f_coverage_from_geom_v10_03(geometry, numeric, numeric, numeric, numeric, boolean)

 

-- DROP FUNCTION xx_99_utils.f_coverage_from_geom_v10_03(geometry, numeric, numeric, numeric, numeric, boolean);

 

CREATE OR REPLACE FUNCTION xx_99_utils.f_coverage_from_geom_v10_03(

    IN in_geom geometry,

    IN cover_largeur numeric,

    IN cover_hauteur numeric,

    IN pc_bordure_planches_contigues numeric,

    IN facteur_div_big_parts numeric DEFAULT 5.0,

    IN call_in_create_table_ddl boolean DEFAULT false)

  RETURNS TABLE(cover_num integer, cover_nb_total integer, geom_cover geometry, geom_covered geometry) AS

$BODY$

DECLARE

/*

AUTHOR : A RIVIERE

note_version

 

V10_03 :

ajout du user_name pour le nom des tables temporaires

+ ajout

 

 

V10_02 :

Ajout du paramètre :

call_in_create_table_ddl

* si FASLE  : alors il n'y aura pas de table temporaire de créée, le traitement sera plus lent.

Cette option est indispensable lors de l'appel de cette fonction dans une select seul (ex : pour QGIS qui va affichier une vm (il faut passer par une vm et non une vue QGIS passe en Read Only mode ))

, enxemple de vm affichée par QGIS : m085_agriculture_outils_structures_agricoles.vm_dpi_planche_impression (la vm est rafraichie automatiqument par un trigger sur modif dans la table m085_agriculture_outils_structures_agricoles.t_add_current_dossier_saisie_sig)

* si TRUE : à utlisiser lorsque la requète est appelée dans une instruction qui créé une table, afin d'augmenter la rapidité du traitement (utilisation de tables temporaire). A utiliser lorsque le résyultat est stocké dans une table via create table.

 

v_08

 

gestion de l'ordre des planche

note_version 03

traitement des objets plus grands que la zone d'impression

Nécessite  : xx_99_utils.f_makegrid_2d( bound_polygon geometry,

    grid_step integer,

    metric_srid integer DEFAULT 28408)

attention préférer st_multi(ST_Collect (p.geom))  plutot que ST_union (qui va fusionner les objets qui se touchent)

note version 02

 

indépendant du SRID :  doit fonctionner en 2154 et en 4326 par exemple

*/

 

-- in_geom                                                                                                                                   : géometrie ou union de geometrie à imprimer

-- cover_largeur                                                                                                        : largeur de la planche à imprimer en unité de terrain

-- cover_hauteur                                                                                                       : hauteur de la planche à imprimer en unité de terrain 

-- pc_cover_recouvrement_planches_contigues                : pourcentage de recouvrement des planches contigues

-- cover_pc_marge_border_cover                         : pourcentage de bordure non contenant des objets ciblés

-- cover_pc_tol_diminution_marge_border_cover           : pc de diminution de la marge acceptable pour optimiser le nombre de planches en sortie

 

 

-- retourne :

-- geom_union_enveloppe  : couvre l'ensemble des planches (cadre du plan d'assemblage) pour un id_publi_prop

-- geom_planche_enveloppe  :  cadre de la planche

-- geom_planche_objet : objet(s) en l’occurrence parcelles cadastrales visibles sur la planche

-- planche_num :  numéro de la planche

-- planche_nombre_total : nombre total de planche pour un id_publi_prop

 

/*

 

Permet de retourner autant de coverage que de géometries injectées (optimisation de l'impression)

 

Exemple d'appel dans un select  :

 

select

row_number() over() as gid

,listing.id_publi_post

,listing.groupe_name

,listing.geom_multi_collect ::geometry(multipolygon,2154) geom_multi_collect

,cov.cover_num planche_num

,cov.cover_nb_total planche_nombre_total

,cov.geom_cover as geom_planche_enveloppe

,cov.geom_covered as  geom_planche_objet

 

from (

SELECT

row_number() over()::int as id_publi_post

, groupe_name, ST_multi(ST_CollectionExtract(ST_collect(geom),3)) as geom_multi_collect

from xx_99_utils.t_test_cover_objets group by groupe_name

)

as listing

, LATERAL (SELECT cov.cover_num,

                    cov.cover_nb_total,

                    cov.geom_cover::geometry(Polygon,2154) AS geom_cover,

                    cov.geom_covered::geometry(MultiPolygon,2154) AS geom_covered

                   FROM xx_99_utils.f_coverage_from_geom_v10_03(listing.geom_multi_collect, 15000::numeric, 15000::numeric, 0::numeric, 5, FALSE) cov(cover_num, cover_nb_total, geom_cover, geom_covered)

           )   cov

 

 

Exemple d'apel en création de table   :

DROP table if exists xx_99_utils.t_test_cover_objets_result;

CREATE table xx_99_utils.t_test_cover_objets_result as

select

row_number() over() as gid

,listing.id_publi_post

,

listing.groupe_name

 

,listing.geom_multi_collect ::geometry(multipolygon,2154) geom_multi_collect

 

,cov.cover_num planche_num

,cov.cover_nb_total planche_nombre_total

,cov.geom_cover as geom_planche_enveloppe

,cov.geom_covered as  geom_planche_objet

 

 

from (

SELECT

row_number() over()::int as id_publi_post

, groupe_name, ST_multi(ST_CollectionExtract(ST_collect(geom),3)) as geom_multi_collect

from xx_99_utils.t_test_cover_objets group by groupe_name

)

as listing

, LATERAL (SELECT cov.cover_num,

                    cov.cover_nb_total,

                    cov.geom_cover::geometry(Polygon,2154) AS geom_cover,

                    cov.geom_covered::geometry(MultiPolygon,2154) AS geom_covered

                   FROM xx_99_utils.f_coverage_from_geom_v10_03(listing.geom_multi_collect, 15000::numeric, 15000::numeric, 0::numeric, 5, TRUE) cov(cover_num, cover_nb_total, geom_cover, geom_covered)

           )   cov

 

Exemple d'appel : (cadastre)

 

select

listing.id_publi_prop,

listing.publipost_prop_nom,

listing.publipost_prop_adresse1,

listing.publipost_prop_adresse2,

listing.publipost_prop_adresse3,

listing.publipost_prop_adresse4,

listing.publipost_lst_pacelles

,ST_Envelope(listing.geom_union)::geometry(polygon, 2154) AS geom_union_enveloppe

,listing.geom_union::geometry(multipolygon,2154) geom_union_objet

 

,cov.cover_num planche_num

,cov.cover_nb_total planche_nombre_total

,cov.geom_cover as geom_planche_enveloppe

,cov.geom_covered as  geom_planche_objet

 

 

from (

SELECT row_number() over()::int as id_publi_prop,* from xx_99_utils.f_cadastre_rtn_publipostage_proprios_from_geom_v_plug_cad_1_4((select st_multi(ST_Collect (geom)) from xx_99_utils.t_test_extraction_cad ),true)

)

as listing

, LATERAL (SELECT cov.cover_num,

                    cov.cover_nb_total,

                    cov.geom_cover::geometry(Polygon,2154) AS geom_cover,

                    cov.geom_covered::geometry(MultiPolygon,2154) AS geom_covered

                   FROM xx_99_utils.f_coverage_from_geom_v10_03(listing.geom_union, 2000::numeric, 2000::numeric, 5::numeric, 5, 0) cov(cover_num, cover_nb_total, geom_cover, geom_covered)

           )   cov

                  

 

 

 

*/

 

 

mode_debug BOOLEAN := FALSE ; ---true;  -- TRUE  renvoi des notices

--mode_debug BOOLEAN := TRUE ;

 

 

-- la création de table temporaire rend le traitement plsu rapide mais n'est pas accessible pour une mat view  (sécurity restriction)

mode_creation_table_temp BOOLEAN:= call_in_create_table_ddl;

--mode_creation_table_temp BOOLEAN:= TRUE;

 

 

 

name_table_temp_supercover text:='temp_supercover_'||current_user ;

name_table_temp_cover text :='temp_over_'||current_user ;

mode_debug_schema text;

mode_debug_temp TEXT;

sql_obj TEXT;

sql_obj_up_to_cover TEXT;

sql_obj_not_up_to_cover_and_not_covered  TEXT;

sql_super_cover_for_obj_not_up_to_cover_and_not_covered TEXT;

 

 

 

rcd_obj RECORD;

rcd_obj_up_to_cover RECORD;

rcd_obj_not_up_to_cover_and_not_covered  RECORD;

rcd_super_cover_for_obj_not_up_to_cover_and_not_covered RECORD;

 

rcd_obj_small RECORD;

 

 

bbox_all_x_min numeric; -- x min de l'enveloppe de la geometrie en entrée

bbox_all_x_max numeric;

 

bbox_all_y_min numeric;

bbox_all_y_max numeric;

bbox_all_hauteur numeric; -- hauteur de l'enveloppe de la geometrie en entrée

 

 

bbox_dump_largeur numeric; -- largeur de l'enveloppe d'une geometrie dumpées

bbox_dump_hauteur numeric; -- hauteur de l'enveloppe d'une geometrie dumpées

 

cov_xcentroid numeric;

cov_ycentroid numeric;

 

--cov_pointLowLeft geometry(point, 2154); -- erreur en restore sur vm

--donc test:

cov_pointLowLeft geometry;

 

--cov_pointUpRight geometry(point, 2154);  -- erreur en restore sur vm

--donc test

cov_pointUpRight geometry;

 

 

ccount int;

 

--sql TEXT;

sql_super_cover TEXT;

sql_cover_prepare TEXT;

 

v_id int;

v_xmin int;

v_ymin int;

v_xmax int;

v_ymax int;

 

buff_recherche_proxi INT ; --valeur du buffer de recherche des objets proches

 

c_chevauchement int; -- distance de recouvrement

 

chevauchement_x  numeric;

 

chevauchement_y numeric;

 

v_nb_hauteur int;

 

v_nb_largeur int;

 

i int;

j int;

 

nb_grp_objets int;

 

Exmin int;

Exmax INT;

Eymin int;

Eymax INT;

 

rtn record;

 

ql_inPoly_AsT text;

 

ql_cover_print_AsT Text;

ql_cover_find_AsT Text;

 

 

 

test_passe_01_num int;

 

tmp_cover_num INT;

 

largeur_cover_marge_et_tolerance NUMERIC;

hauteur_cover_marge_et_tolerance NUMERIC;

 

nb_obj_not_up_to_cover_to_be_covered INT;

 

nb_cover int;

 

input_srid int;

 

 

BEGIN

 

SET client_min_messages = ERROR;

if mode_debug THEN

   SET client_min_messages = NOTICE; -- pour le debug

END IF;

 

input_srid = ST_SRID(in_geom);  -- récupère le SRID de la géométrie en entrée

 

 

--c_chevauchement = (floor(cover_largeur* pc_cover_recouvrement_planches_contigues/100.00))::int;

 

 

--RAISE NOTICE 'c_chevauchement : %', c_chevauchement;

 

 

 

 

ql_inPoly_AsT  := QUOTE_LITERAL(ST_ASEWKT(in_geom::geometry));

test_passe_01_num = 0;

 

-- nb d'objets

 

largeur_cover_marge_et_tolerance = cover_largeur;

 

hauteur_cover_marge_et_tolerance = cover_hauteur;

 

 

RAISE NOTICE 'largeur_cover_marge_et_tolerance: %', largeur_cover_marge_et_tolerance;

RAISE NOTICE 'hauteur_cover_marge_et_tolerance: %', hauteur_cover_marge_et_tolerance;

 

 

--return 1;

 

-- TODO : traitement des objets plus grands que la zone d'impression (cover)

 

--debug :

 

if mode_creation_table_temp = FALSE THEN

    mode_debug_schema := 'xx_99_utils.';

    mode_debug_temp := '';

ELSE

    mode_debug_schema := '';

    mode_debug_temp := 'TEMP';

END IF;

 

 

 

EXECUTE 'DROP TABLE IF EXISTS '|| mode_debug_schema || name_table_temp_supercover ||' ;

CREATE '|| mode_debug_temp || ' TABLE '|| mode_debug_schema || name_table_temp_supercover ||'

(

  id_dump INT,

  dump_geom geometry,

  is_up_to_cover boolean,

  is_covered_in_tmp_cover boolean,

  super_cover geometry(polygon, ' || input_srid ||')

)';

--(multipolygon,2154)

EXECUTE 'TRUNCATE '|| mode_debug_schema || name_table_temp_supercover ;

/*

Ajout dans la table super_cover l'ensemble des super_coverages

c.a.d.: box2D par objet qui correspond a l'ensemble de l'emprise de tous les covers : chaque bones min/max

4 orientations de coverage pour chacunes des limites des objets

*/

sql_super_cover :='

        WITH

        

        wdump as ( 

          SELECT 

            

              (ST_DUMP (ST_MULTI(ST_CollectionExtract(ST_MakeValid('|| ql_inPoly_AsT ||'::geometry),3)))).geom dump_geom

           )

        , wdump_01 as (SELECT  row_number() over() as id_dump_01,   dump_geom FROM  wdump)         

        , wdump_test_big as (     

               SELECT

                 id_dump_01

               , dump_geom

               , CASE  WHEN (st_xmax(dump_geom) - st_xmin(dump_geom)) > ' || largeur_cover_marge_et_tolerance ||'

                           OR  (st_ymax(dump_geom) - st_ymin(dump_geom)) > ' || hauteur_cover_marge_et_tolerance ||'

                           THEN TRUE  ELSE FALSE  END::boolean  AS is_up_to_cover

               ,  FALSE::boolean  AS is_covered_in_tmp_cover

               FROM wdump_01

             )

 

         , w_clip_dump_if_necessary  as  (

              WITH

                big as (select id_dump_01, dump_geom from wdump_test_big where is_up_to_cover IS TRUE)

               , grid as (select id_dump_01, dump_geom

               ,  (st_dump(xx_99_utils.f_geo_makegrid_2d(dump_geom,'|| LEAST(largeur_cover_marge_et_tolerance,hauteur_cover_marge_et_tolerance)/facteur_div_big_parts ||'::int,'||input_srid||'))).geom as grid_geom from big)

               SELECT distinct grid.grid_geom as  dump_geom from grid where  ST_intersects(dump_geom,grid_geom)

               )

          , w_union_big_and_small as (

            select dump_geom , is_up_to_cover from wdump_test_big where is_up_to_cover IS FALSE

            union all

            SELECT dump_geom , FALSE FROM w_clip_dump_if_necessary

            )

 

          ,  wdump_with_id as (

            SELECT 

               row_number() over(ORDER BY ST_Area(dump_geom) DESC)   as id_dump

               ,* ,  FALSE::boolean  AS is_covered_in_tmp_cover

               from w_union_big_and_small

            )

           

        INSERT INTO  '|| mode_debug_schema || name_table_temp_supercover || ' (

              id_dump

            , dump_geom

            , is_up_to_cover

            , is_covered_in_tmp_cover

            , super_cover

            )

         SELECT

           *

         , ST_SetSRID(  ST_MakeBox2D( ST_MakePoint(             ST_Xmax( ST_Envelope(obj.dump_geom) ) - ' || largeur_cover_marge_et_tolerance ||'

                                                     ,ST_Ymax( ST_Envelope(obj.dump_geom) ) - ' ||hauteur_cover_marge_et_tolerance || '

                                                    )

                                      ,ST_MakePoint(         ST_Xmin( ST_Envelope(dump_geom) ) + ' || largeur_cover_marge_et_tolerance ||'

                                                     ,ST_Ymin( ST_Envelope(obj.dump_geom) ) + ' ||hauteur_cover_marge_et_tolerance || '

                                                     )

                                    )

                      , '||input_srid||'

                      ) AS super_cover

         FROM wdump_with_id obj'   --ON COMMIT DROP'

        ;--WHERE is_up_to_cover IS FALSE AND covered_in_tmp_cover_num IS NULL

 

 

RAISE NOTICE 'sql_super_cover: %', sql_super_cover;

EXECUTE sql_super_cover;

EXECUTE 'CREATE  INDEX sidx_temp_super_cover_dump_geom_' || current_user ||'

  ON '|| mode_debug_schema || name_table_temp_supercover || '

  USING gist

  (dump_geom);

  ';

EXECUTE 'CREATE  INDEX sidx_temp_super_cover_super_cover_' || current_user ||'

  ON '|| mode_debug_schema || name_table_temp_supercover || '

  USING gist

  (super_cover);

  ';

 

 

EXECUTE ' DROP TABLE IF EXISTS  '|| mode_debug_schema ||  name_table_temp_cover ;

EXECUTE '

CREATE  '|| mode_debug_temp || ' TABLE  IF NOT EXISTS  '|| mode_debug_schema || name_table_temp_cover  || ' (

     cover_num INT

   , cover_nb_total INT

   , geom_cover geometry(polygon)

   , geom_covered geometry(multipolygon)

   , geom_enveloppe geometry(polygon)

)';

 

 

 

tmp_cover_num =0;

EXECUTE 'TRUNCATE  '|| mode_debug_schema || name_table_temp_cover ;

/*

N'est plus nécessaire

sql_obj_up_to_cover = 'SELECT * FROM temp_supercover WHERE is_up_to_cover IS TRUE';

 

FOR rcd_obj_up_to_cover IN  EXECUTE sql_obj_up_to_cover 

            LOOP

                        -- TODO si objet > cover nom pas prendre en compte le % de tolérance

                                   --return 2;

            END LOOP;

 

*/

 

 

EXECUTE ' SELECT count(id_dump) from '|| mode_debug_schema || name_table_temp_supercover ||' WHERE is_up_to_cover IS FALSE;' INTO nb_obj_not_up_to_cover_to_be_covered;

 

/*

if mode_creation_table_temp = FALSE THEN

   

   nb_obj_not_up_to_cover_to_be_covered:=count(id_dump) from xx_99_utils.temp_supercover WHERE is_up_to_cover IS FALSE;

   ELSE

   EXECUTE ' SELECT count(id_dump) from '|| mode_debug_schema || name_table_temp_cover ||' WHERE is_up_to_cover IS FALSE;' INTO nb_obj_not_up_to_cover_to_be_covered;

   --nb_obj_not_up_to_cover_to_be_covered:=count(id_dump) from temp_supercover WHERE is_up_to_cover IS FALSE;

END IF;

--RAISE NOTICE 'nb_obj_not_up_to_cover_to_be_covered: %', nb_obj_not_up_to_cover_to_be_covered;

 

*/

 

sql_cover_prepare :=

 ' WITH w_prepare as (SELECT

            super_c1.*

          , count(super_c2.dump_geom) nb_obj_in_super_cover

          , ST_SetSRID(

                  ST_MakeBox2D(

                     ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom)))

                      ,- ' || largeur_cover_marge_et_tolerance/2. ||

                     ',- ' || hauteur_cover_marge_et_tolerance/2. || '

                     )'  ||

                  ', ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom)))

                        ,+ ' || largeur_cover_marge_et_tolerance/2. || '

                        ,+ ' || hauteur_cover_marge_et_tolerance/2. || '

                     )

                  ) 

               , '||input_srid||'

            ) AS  cover_contenance

          , ST_SetSRID(

               ST_MakeBox2D(

                   ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom))),-' ||cover_largeur/2. ||' ,- '|| cover_hauteur/2. || ')

                  ,ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom))),+' ||cover_largeur/2. ||' ,+' || cover_hauteur/2. || ')

               )

               , '||input_srid||'

            ) AS cover_print

           , ST_Multi(ST_Union(super_c2.dump_geom)) as geom_covered

           , ST_Envelope(ST_Union(super_c2.dump_geom)) as geom_enveloppe

 

         FROM  '|| mode_debug_schema || name_table_temp_supercover ||' super_c1

             , '|| mode_debug_schema || name_table_temp_supercover ||' super_c2

         WHERE

                ST_intersects(super_c1.super_cover, super_c2.dump_geom)

            AND ST_Contains (super_c1.super_cover, super_c2.dump_geom)

            AND super_c1.is_up_to_cover IS FALSE

            AND super_c1.is_covered_in_tmp_cover IS FALSE

            AND super_c2.is_up_to_cover IS FALSE

            AND super_c2.is_covered_in_tmp_cover IS FALSE

 

         GROUP BY

              super_c1.id_dump

            , super_c1.dump_geom

            , super_c1.is_up_to_cover

            , super_c1.is_covered_in_tmp_cover

            , super_c1.super_cover

       )

      SELECT  super_c1.*

            , sum(super_c2.nb_obj_in_super_cover) AS  densite_d_objets

          FROM   w_prepare super_c1

               , w_prepare super_c2

          WHERE

               ST_intersects(super_c1.super_cover, super_c2.dump_geom)

           AND ST_Contains (super_c1.super_cover, super_c2.dump_geom)

         GROUP BY

              super_c1.id_dump

            , super_c1.dump_geom

            , super_c1.is_up_to_cover

            , super_c1.is_covered_in_tmp_cover

            , super_c1.super_cover

            , super_c1.nb_obj_in_super_cover

            , super_c1.cover_print

            , super_c1.geom_covered

            , super_c1.cover_contenance

            , super_c1.geom_enveloppe

         ORDER BY

              super_c1.nb_obj_in_super_cover ASC

            , densite_d_objets ASC

         LIMIT 1 '

         ;

--ORDER BY super_c1.nb_obj_in_super_cover ASC, densite_d_objets ASC

FOR i in 1.. nb_obj_not_up_to_cover_to_be_covered LOOP -- pour chaque objet

   tmp_cover_num := tmp_cover_num + 1;

        --RAISE NOTICE 'i: %', i;

   if tmp_cover_num <= 3 THEN

      RAISE NOTICE 'sql_cover_prepare: %', sql_cover_prepare;

   END IF;

   FOR rcd_obj_small IN EXECUTE sql_cover_prepare LOOP

      IF rcd_obj_small.id_dump IS NOT NULL THEN

               

                                                            j:= rcd_obj_small.id_dump;

               

                ql_cover_print_AsT   := QUOTE_LITERAL(ST_ASEWKT(in_geom::geometry));

 

               

                  EXECUTE '

                   INSERT INTO '|| mode_debug_schema || name_table_temp_cover || ' ( cover_num, geom_cover, geom_covered, geom_enveloppe )

                        VALUES (' || tmp_cover_num::text ||'

                           ,'|| QUOTE_LITERAL(ST_ASEWKT(rcd_obj_small.cover_print::geometry)) ||'::geometry

                           ,'|| QUOTE_LITERAL(ST_ASEWKT(rcd_obj_small.geom_covered::geometry)) ||'::geometry

                           ,'|| QUOTE_LITERAL(ST_ASEWKT(rcd_obj_small.geom_enveloppe::geometry))||'::geometry ); 

                  DELETE

                     FROM '|| mode_debug_schema || name_table_temp_supercover ||'

                     WHERE

                     ST_Intersects( '|| QUOTE_LITERAL(ST_ASEWKT(rcd_obj_small.cover_print::geometry)) ||'::geometry, dump_geom) 

                     AND ST_Contains( st_buffer('|| QUOTE_LITERAL(ST_ASEWKT(rcd_obj_small.cover_print::geometry)) ||'::geometry, 0.1), dump_geom) ; ';

 

                 /*

                ELSE

                     INSERT INTO temp_cover ( cover_num,geom_cover, geom_covered, geom_enveloppe )

                        VALUES (tmp_cover_num,rcd_obj_small.cover_print ,rcd_obj_small.geom_covered, rcd_obj_small.geom_enveloppe );

                  DELETE

                     FROM temp_supercover

                     WHERE

                     ST_Intersects( rcd_obj_small.cover_print, dump_geom)  -- cover_contenance

                     AND ST_Contains( st_buffer(rcd_obj_small.cover_print, 0.1), dump_geom) ;    -- cover_contenance

                END IF;

             */

      END IF;

 

   END LOOP;

END LOOP;

 

EXECUTE ' SELECT count(temp_cover.cover_num) FROM '|| mode_debug_schema || name_table_temp_cover ||' temp_cover; ' INTO nb_cover;

 

RETURN QUERY EXECUTE '

With w_prepare as (SELECT

         

           '|| nb_cover ||' ::int as cover_nb_total,

           temp_cover.geom_cover::geometry(polygon) ,

           temp_cover.geom_covered::geometry(multipolygon)

         

           FROM '|| mode_debug_schema || name_table_temp_cover ||' as temp_cover

           order by ST_XMin(temp_cover.geom_cover) ASC, ST_YMin(temp_cover.geom_cover) ASC

      )

      select   row_number() over ()::int  as cover_num,

      * from w_prepare ;

    ';

/*

if mode_creation_table_temp =FALSE THEN

    --nb_cover := count(temp_cover.cover_num) FROM xx_99_utils.temp_cover;

    RETURN QUERY

      With w_prepare as (SELECT

         

           nb_cover::int as cover_nb_total,

           temp_cover.geom_cover::geometry(polygon) ,

           temp_cover.geom_covered::geometry(multipolygon)

         

           FROM xx_99_utils.temp_cover

           order by ST_XMin(temp_cover.geom_cover) ASC, ST_YMin(temp_cover.geom_cover) ASC

      )

      select   row_number() over ()::int  as cover_num,

      * from w_prepare ;

ELSE

     --nb_cover := count(temp_cover.cover_num) FROM temp_cover;

     RETURN QUERY

      With w_prepare as (SELECT

         

           nb_cover::int as cover_nb_total,

           temp_cover.geom_cover::geometry(polygon) ,

           temp_cover.geom_covered::geometry(multipolygon)

         

           FROM temp_cover

           order by ST_XMin(temp_cover.geom_cover) ASC, ST_YMin(temp_cover.geom_cover) ASC

      )

      select   row_number() over ()::int  as cover_num,

      * from w_prepare ;

END IF;

*/

 

 

 

END;

$BODY$

  LANGUAGE plpgsql VOLATILE SECURITY DEFINER

  COST 100

  ROWS 1000;
