
CREATE OR REPLACE FUNCTION xx_99_utils.f_cadastre_rtn_publipostage_proprios_from_geom_v_plug_cad_1_3(
    IN ins_geom geometry,
    IN ins_is_seulement_destinataire_avis_impot boolean DEFAULT false)
  RETURNS TABLE(publipost_prop_nom character varying, publipost_prop_adresse1 character varying, publipost_prop_adresse2 character varying, publipost_prop_adresse3 character varying, publipost_prop_adresse4 character varying, publipost_lst_pacelles text, geom_union geometry) AS
$BODY$   
/*
-- note se base sur f_cadastre_rtn_infos_parc_et_proprios_from_geom_v_plug_cad_1_3
entrées : 
1)ins_geom : géométrie de recherche (intersection)
2)ins_is_seulement_destinataire_avis_impot : défaut FALSE, sinon TRUE pour ne rechercher que le destinataire de l'avis d'imposition (une occurence par parcelle) 

génère un listing des propriétaires uniques selon leurs adresses , liste les parcelles de ce propriétaire et renvoie la géométrie de l'union des parcelle par propriétaire
pe


Exemple d'appel : 
select * from xx_99_utils.f_cadastre_rtn_publipostage_proprios_from_geom_v_plug_cad_1_3((select st_union(geom) from xx_99_utils.t_test_extraction_cad ))


sortie :
  publipost_prop_nom character varying,  -- nom
  publipost_prop_adresse1 character varying(30), -- adresses1à 4 à utiliser en publipostage
  publipost_prop_adresse2 character varying(36), -- adresses1à 4 à utiliser en publipostage
  publipost_prop_adresse3 character varying(30), -- adresses1à 4 à utiliser en publipostage
  publipost_prop_adresse4 character varying(32), -- adresses1à 4 à utiliser en publipostage
  publipost_lst_pacelles text, -- listing des parcelles (dept) commune 1 : selection A : 1,2,10
  geom_union geometry(multipolygon, 2154)  -- ensemble de toutes les parcelles concernées

*/
with
w_assemblage_des_sections AS (
select --distinct on (publipost_prop_nom, publipost_prop_adresse1,publipost_prop_adresse2,publipost_prop_adresse3, publipost_prop_adresse4) 


cad.publipost_prop_nom,
cad.publipost_prop_adresse1,
cad.publipost_prop_adresse2,
cad.publipost_prop_adresse3,
cad.publipost_prop_adresse4,
cad.parc_ccodep,
cad.parc_libcom,

--'('||(select distinct(cad.parc_ccodep))  || ')' ||(select distinct (cad.parc_libcom)) ||
'Section ' || trim(cad.parc_ccosec)  || ' n°' ||  string_agg( cad.parc_dnupla, ',') as lst_parcelles_des_sections--, || string_agg( '(' || (select distinct(parc_ccodep)) || ') ' || (select distinct (parc_libcom)), ' -- ')

,ST_Union(cad.geom) as geom_union
from xx_99_utils.f_cadastre_rtn_infos_parc_et_proprios_from_geom_v_plug_cad_1_3(ins_geom::geometry, ins_is_seulement_destinataire_avis_impot )  cad

group by cad.publipost_prop_nom, cad.publipost_prop_adresse1,cad.publipost_prop_adresse2,cad.publipost_prop_adresse3, cad.publipost_prop_adresse4,cad.parc_ccodep,cad.parc_libcom, cad.parc_ccosec --, parc_dnupla --cad.parc_ccodep, cad.parc_libcom
order by cad.parc_ccosec ASC
)

,w_assemblage_des_communes as (

select 
w.publipost_prop_nom,
w.publipost_prop_adresse1,
w.publipost_prop_adresse2,
w.publipost_prop_adresse3,
w.publipost_prop_adresse4,
w.parc_ccodep,
w.parc_libcom || ': ' || string_agg( w.lst_parcelles_des_sections, ' et ') as lst_parcelles_des_communes
,ST_Union(w.geom_union) as geom_union


 from w_assemblage_des_sections w 
 group by w.publipost_prop_nom, w.publipost_prop_adresse1,w.publipost_prop_adresse2,w.publipost_prop_adresse3, w.publipost_prop_adresse4, w.parc_ccodep,w.parc_libcom
 order by  w.parc_libcom ASC

)

,w_assemblage_des_departements as (

select 
w.publipost_prop_nom,
w.publipost_prop_adresse1,
w.publipost_prop_adresse2,
w.publipost_prop_adresse3,
w.publipost_prop_adresse4,
'(' || w.parc_ccodep ||') ' ||  string_agg( w.lst_parcelles_des_communes, ' - ')  as lst_parcelles_des_departements

,ST_Union(w.geom_union) as geom_union

 from w_assemblage_des_communes w 
 group by w.publipost_prop_nom, w.publipost_prop_adresse1,w.publipost_prop_adresse2,w.publipost_prop_adresse3, w.publipost_prop_adresse4, w.parc_ccodep
 order by w.parc_ccodep asc
)




,w_assemblage_des_parcelles_d_un_proprio as (

select 
w.publipost_prop_nom,
w.publipost_prop_adresse1,
w.publipost_prop_adresse2,
w.publipost_prop_adresse3,
w.publipost_prop_adresse4,
string_agg( w.lst_parcelles_des_departements, ' ')  as lst_parcelles_des_departements

,ST_Union(w.geom_union) as geom_union

 from w_assemblage_des_departements w 
 group by w.publipost_prop_nom, w.publipost_prop_adresse1,w.publipost_prop_adresse2,w.publipost_prop_adresse3, w.publipost_prop_adresse4
 order by w.publipost_prop_nom
)

select * from w_assemblage_des_parcelles_d_un_proprio
$BODY$
  LANGUAGE sql STABLE STRICT
  COST 100
  ROWS 10000;
