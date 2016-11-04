
CREATE OR REPLACE FUNCTION xx_99_utils.f_coverage_from_geom_v01(
    IN in_geom geometry,
    IN cover_largeur numeric,
    IN cover_hauteur numeric,
    IN pc_cover_recouvrement_planches_contigues numeric,
    IN cover_pc_marge_border_cover integer DEFAULT 5,
    IN cover_pc_tol_diminution_marge_border_cover integer DEFAULT 0)
  RETURNS TABLE(cover_num integer, cover_nb_total integer, geom_cover geometry, geom_covered geometry) AS
$BODY$
DECLARE


-- in_geom 											      : géometrie ou union de geometrie à imprimer
-- cover_largeur 								         : largeur de la planche à imprimer en unité de terrain
-- cover_hauteur 								         : hauteur de la planche à imprimer en unité de terrain  
-- pc_cover_recouvrement_planches_contigues 	   : pourcentage de recouvrement des planches contigues 
-- cover_pc_marge_border_cover 	               : pourcentage de bordure non contenant des objets ciblés
-- cover_pc_tol_diminution_marge_border_cover 	: pc de diminution de la marge acceptable pour optimiser le nombre de planches en sortie


/*

Permet de retourner autant de coverage que de géometries injectées (optimisation de l'impression) 


Exemple d'appel : 





*/

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

sql TEXT;


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


BEGIN




c_chevauchement = (floor(cover_largeur* pc_cover_recouvrement_planches_contigues/100.00))::int;


RAISE NOTICE 'c_chevauchement : %', c_chevauchement;




ql_inPoly_AsT	:= QUOTE_LITERAL(ST_ASEWKT(in_geom::geometry));
test_passe_01_num = 0;

-- nb d'objets 

largeur_cover_marge_et_tolerance = cover_largeur*
																	( 100.00 
																		-(cover_pc_marge_border_cover* 
																						(100.00- 
																							cover_pc_tol_diminution_marge_border_cover
																						)
																						/100.00
																			)
																		)
																		 /100.00;

hauteur_cover_marge_et_tolerance = cover_hauteur*
																	( 100.00 
																		-(cover_pc_marge_border_cover* 
																						(100.00- 
																							cover_pc_tol_diminution_marge_border_cover
																						)
																						/100.00
																			)
																		)
																		 /100.00;


RAISE NOTICE 'largeur_cover_marge_et_tolerance: %', largeur_cover_marge_et_tolerance;
RAISE NOTICE 'hauteur_cover_marge_et_tolerance: %', hauteur_cover_marge_et_tolerance;


--return 1;

-- TODO : traitement des objets plus grands que la zone d'impression (cover)


--EXECUTE 'DROP  TABLE IF EXISTS temp_edenn_supercover ';

EXECUTE 'CREATE TEMP TABLE TABLE IF NOT EXISTS temp_supercover 
(
  id_dump INT,
  dump_geom geometry,
  is_up_to_cover boolean,
  is_covered_in_tmp_cover boolean,
  super_cover geometry
)';

EXECUTE 'TRUNCATE temp_supercover ';
EXECUTE '
        WITH wdump as (
        SELECT  (ST_DUMP ('|| ql_inPoly_AsT ||'::geometry(multipolygon,2154))).geom dump_geom  ) ,       wdump_with_id as ( 	SELECT  row_number() over(ORDER BY ST_Area(dump_geom) DESC)  id_dump,  dump_geom,  CASE  WHEN (st_xmax(dump_geom) - st_xmin(dump_geom)) > ' || largeur_cover_marge_et_tolerance ||' OR  (st_ymax(dump_geom) - st_ymin(dump_geom)) > ' || hauteur_cover_marge_et_tolerance ||' THEN TRUE  ELSE FALSE  END::boolean  AS is_up_to_cover,  FALSE::boolean  AS is_covered_in_tmp_cover FROM wdump  )  
        INSERT INTO  temp_supercover (id_dump, dump_geom, is_up_to_cover, is_covered_in_tmp_cover, 
       super_cover) 
SELECT *, ST_SetSRID(  ST_MakeBox2D( 	ST_MakePoint( 	ST_Xmax( ST_Envelope(obj.dump_geom) ) - ' || largeur_cover_marge_et_tolerance ||', ST_Ymax( ST_Envelope(obj.dump_geom) ) - ' ||hauteur_cover_marge_et_tolerance || '),	ST_MakePoint( 	ST_Xmin( ST_Envelope(dump_geom) ) + ' || largeur_cover_marge_et_tolerance ||' , ST_Ymin( ST_Envelope(obj.dump_geom) ) + ' ||hauteur_cover_marge_et_tolerance || ')), 2154) super_cover from wdump_with_id obj'   --ON COMMIT DROP'
        ;--WHERE is_up_to_cover IS FALSE AND covered_in_tmp_cover_num IS NULL 
--EXECUTE 'DROP  TABLE IF EXISTS temp_edenn_cover ';


EXECUTE 'CREATE  TEMP TABLE  IF NOT EXISTS  temp_cover (cover_num INT, cover_nb_total INT, geom_cover geometry(polygon, 2154)
, geom_covered geometry(multipolygon,2154)
, geom_enveloppe geometry(polygon, 2154)

)'; --ON COMMIT DROP';



tmp_cover_num =0;
EXECUTE 'TRUNCATE temp_cover ';
sql_obj_up_to_cover = 'SELECT * FROM temp_supercover WHERE is_up_to_cover IS TRUE';

FOR rcd_obj_up_to_cover IN  EXECUTE sql_obj_up_to_cover  
	LOOP 
		-- TODO si objet > cover nom pas prendre en compte le % de tolérance
			--return 2;
	END LOOP;





nb_obj_not_up_to_cover_to_be_covered:=count(id_dump) from temp_supercover WHERE is_up_to_cover IS FALSE;

RAISE NOTICE 'nb_obj_not_up_to_cover_to_be_covered: %', nb_obj_not_up_to_cover_to_be_covered;


FOR i in 1.. nb_obj_not_up_to_cover_to_be_covered 
LOOP
        RAISE NOTICE 'i: %', i;
        FOR rcd_obj_small IN EXECUTE '

        WITH w_prepare as (SELECT
          super_c1.*, count(super_c2.dump_geom) nb_obj_in_super_cover,
          ST_SetSRID(ST_MakeBox2D(
          ST_Translate(
          ST_Centroid(
          ST_Envelope(
          ST_Union(super_c2.dump_geom)
          )
          ),- ' || largeur_cover_marge_et_tolerance/2 || 
          ',- ' || hauteur_cover_marge_et_tolerance/2 || '
        )'  ||
        ',ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom))),+ ' || largeur_cover_marge_et_tolerance/2 || ' ,+ ' || hauteur_cover_marge_et_tolerance/2 || ')
), 2154) cover_contenance,
ST_SetSRID(ST_MakeBox2D(ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom))),-' ||cover_largeur/2 ||' ,- '|| cover_hauteur/2 || '
),ST_Translate(ST_Centroid(ST_Envelope(ST_Union(super_c2.dump_geom))),+' ||cover_largeur/2 ||',+' ||cover_hauteur/2 ||')
), 2154) cover_print,
ST_Multi(ST_Union(super_c2.dump_geom)) as geom_covered,
ST_Envelope(ST_Union(super_c2.dump_geom)) as geom_enveloppe

	FROM temp_supercover super_c1, temp_supercover super_c2 
	WHERE 
        super_c1.is_up_to_cover IS FALSE 
        AND  super_c1.is_covered_in_tmp_cover IS FALSE
        AND super_c2.is_up_to_cover IS FALSE 
        AND  super_c2.is_covered_in_tmp_cover IS FALSE
	AND ST_Contains (super_c1.super_cover, super_c2.dump_geom)
	GROUP BY super_c1.id_dump, super_c1.dump_geom, super_c1.is_up_to_cover , super_c1.is_covered_in_tmp_cover , super_c1.super_cover)
	SELECT super_c1.* , sum(super_c2.nb_obj_in_super_cover) densite_d_objets
	 FROM w_prepare super_c1, w_prepare super_c2
	 WHERE ST_Contains (super_c1.super_cover, super_c2.dump_geom)
	 GROUP BY super_c1.id_dump, super_c1.dump_geom, super_c1.is_up_to_cover , super_c1.is_covered_in_tmp_cover , super_c1.super_cover,super_c1.nb_obj_in_super_cover ,super_c1.cover_print, super_c1.geom_covered,super_c1.cover_contenance,super_c1.geom_enveloppe 
	ORDER BY super_c1.nb_obj_in_super_cover ASC, densite_d_objets ASC
	LIMIT 1 ' 
	LOOP
        IF rcd_obj_small.id_dump IS NOT NULL THEN
                
								j:= rcd_obj_small.id_dump;
                tmp_cover_num := tmp_cover_num +1;
                ql_cover_print_AsT	:= QUOTE_LITERAL(ST_ASEWKT(in_geom::geometry));
                INSERT INTO temp_cover ( cover_num,geom_cover, geom_covered, geom_enveloppe ) VALUES (tmp_cover_num,rcd_obj_small.cover_print,rcd_obj_small.geom_covered, rcd_obj_small.geom_enveloppe ); 
                DELETE FROM temp_supercover WHERE ST_Contains( rcd_obj_small.cover_contenance, dump_geom) ;
                RAISE NOTICE 'j: %', j;
	END IF;

        END LOOP;
END LOOP;

nb_cover := count(temp_cover.cover_num) FROM temp_cover;
RETURN QUERY SELECT 
        temp_cover.cover_num::int, 
        nb_cover::int as cover_nb_total, 
        temp_cover.geom_cover::geometry(polygon, 2154) ,
        temp_cover.geom_covered::geometry(multipolygon, 2154) 
        --,temp_cover.geom_enveloppe::geometry(polygon, 2154) 
        FROM temp_cover ;



--EXECUTE 'DROP  TABLE IF EXISTS temp_supercover ';
--EXECUTE 'DROP  TABLE IF EXISTS temp_cover ';
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;
