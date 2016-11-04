CREATE OR REPLACE FUNCTION xx_99_utils.f_cadastre_rtn_infos_parc_et_proprios_from_geom_v_plug_cad_1_3(
    IN insgeom geometry,
    IN ins_is_seulement_destinataire_avis_impot boolean DEFAULT false)
  RETURNS TABLE(geo_parcelle character varying, geom geometry, parc_jdatat date, parc_ccodep character varying, parc_ccocom character varying, parc_libcom character varying, parc_ccosec character varying, parc_dnupla character varying, parc_dnvoiri character varying, parc_cconvo character varying, parc_dvoilib character varying, parc_dnupro character varying, proprio_ccodro_lib character varying, proprio_ccodem_lib character varying, proprio_gdesip character varying, proprio_gtoper character varying, proprio_dformjur character varying, proprio_dqualp character varying, proprio_ddenom character varying, proprio_dnomus character varying, proprio_dprnus character varying, proprio_jdatnss date, proprio_dldnss character varying, proprio_epxnee character varying, proprio_dnomcp character varying, proprio_dprncp character varying, proprio_dlign3 character varying, proprio_dlign4 character varying, proprio_dlign5 character varying, proprio_dlign6 character varying, publipost_prop_nom character varying, publipost_prop_adresse1 character varying, publipost_prop_adresse2 character varying, publipost_prop_adresse3 character varying, publipost_prop_adresse4 character varying, geom_etiquette_position_point geometry, proprio_dnomlp character varying, proprio_dprnlp character varying) AS
$BODY$
/*	
Pour chaque parcelle qui intersecte la geom en entrée, 
Renvoie des informations concernant la parcelle et le(s) propriétaire(s) 

entrées : 
1)ins_geom : géométrie de recherche (intersection)
2)ins_is_seulement_destinataire_avis_impot : défaut FALSE, sinon TRUE pour ne rechercher que le destinataire de l'avis d'imposition (une occurence par parcelle) 

exemple d'appel : 


select * from xx_99_utils.f_cadastre_rtn_infos_parc_et_proprios_from_geom_v_plug_cad_1_3((select st_union(geom) from xx_99_utils.t_test_extraction_cad ))  -- utilisation de la valeur par défaut false pour ins_is_seulement_destinataire_avis_impot

pour n'avoir que les destinataire de l'avis d'imposition :
select * from xx_99_utils.f_cadastre_rtn_infos_parc_et_proprios_from_geom_v_plug_cad_1_3((select st_union(geom) from xx_99_utils.t_test_extraction_cad ), TRUE) 



note : 
  proprio_gdesip character varying(1), -- indicateur du destinataire de l’avis d’imposition - 1 = oui, 0 = non
  


pour le listing de publippostage :


-- version plugin cadastre 1.3

attention : 
  proprio_gdesip character varying(1), -- indicateur du destinataire de l’avis d’imposition - 1 = oui, 0 = non

*/	--
declare
c_schemaname_cadastre text := 'cadastre_actuel';
c_tablename_parcelle text := 'parcelle' ;  
c_tablename_proprio text := 'proprietaire' ;  
rq_find record;
string_sql TEXT;

BEGIN
 

string_sql := $s$
select 
	geo_parcelle.geo_parcelle,	-- identifiant unique de parcelle
	geo_parcelle.geom, -- geometry(MultiPolygon,2154)

      	parcelle.jdatat parc_jdatat, -- Date de l acte - jjmmaaaa
      	parcelle.ccodep parc_ccodep , -- code département -
      	parcelle.ccocom parc_ccocom, -- Code commune INSEE ou DGI d’arrondissement -
      	TRIM(commune.libcom)::character varying(30) as  parc_libcom  ,  -- nom de la commune de la parcelle
      	parcelle.ccosec parc_ccosec  , -- Section cadastrale -
      	ltrim(parcelle.dnupla, '0')::character varying(4)  parc_dnupla, -- Numéro de plan -

      	parcelle.dnvoiri parc_dnvoiri    , -- Numéro de voirie -
      	parcelle.cconvo parc_cconvo    , -- Code nature de la voie
      	parcelle.dvoilib parc_dvoilib    , -- Libellé de la voie


      	parcelle.dnupro   parc_dnupro    , -- Compte communal du propriétaire de la parcelle -

      	ccodro.ccodro_lib  proprio_ccodro_lib    , -- code du droit réel ou particulier - Nouveau code en 2009 : C (fiduciaire)
      	ccodem.ccodem_lib  proprio_ccodem_lib    , -- code du démembrement/indivision - C S L I V
      	proprietaire.gdesip   proprio_gdesip    , -- indicateur du destinataire de l’avis d’imposition - 1 = oui    , 0 = non
      	proprietaire.gtoper   proprio_gtoper    , -- indicateur de personne physique ou morale - 1 = physique, 2 = morale
                                                -- [  donc si morale (2)  utiliser proprio_ddenom 
                                                -- si physique utiliser la batterie de colonnes qui suit]
                                                --Voir publipost_prop_nom (champ qui associe ces éléments)
       

      	proprietaire.dformjur  proprio_dformjur    , -- Forme juridique (Depuis 2013)
      	proprietaire.dqualp   proprio_dqualp    , -- Qualité abrégée - M , MME ou MLE
      	proprietaire.ddenom  proprio_ddenom    , -- Dénomination de personne physique ou morale -
      	proprietaire.dnomus   proprio_dnomus    , -- Nom d'usage (Depuis 2015)
      	proprietaire.dprnus   proprio_dprnus    , -- Prénom d'usage (Depuis 2015)


      	proprietaire.jdatnss  proprio_jdatnss    , -- date de naissance - sous la forme jj/mm/aaaa
      	proprietaire.dldnss   proprio_dldnss    , -- lieu de naissance -
      	proprietaire.epxnee   proprio_epxnee    , -- mention du complément - EPX ou NEE si complément
      	proprietaire.dnomcp   proprio_dnomcp    , -- Nom complément -
      	proprietaire.dprncp  proprio_dprncp    , -- Prénoms associés au complément -
      	proprietaire.dlign3  proprio_dlign3    , -- 3eme ligne d’adresse -
      	proprietaire.dlign4  proprio_dlign4    , -- 4eme ligne d’adresse -
      	proprietaire.dlign5  proprio_dlign5    , -- 5eme ligne d’adresse -
      	proprietaire.dlign6  proprio_dlign6 ,     -- 6eme ligne d’adresse -

      /*case when proprietaire.gtoper = '1' THEN ''
         WHEN  proprietaire.gtoper = '2' THEN coalesce(proprietaire.dformjur,'') || ' ' || coalesce( proprietaire.ddenom,'')
         ELSE 'gtoper non référencé' END ::character varying(60)
      as publipost_prop_societe,
      case when proprietaire.gtoper = '1' THEN proprietaire.dqualp
         WHEN  proprietaire.gtoper = '2' THEN ''
         ELSE 'gtoper non référencé' END ::character varying(3)
      as publipost_prop_titre,
       case when proprietaire.gtoper = '1' THEN proprietaire.dnomus
         WHEN  proprietaire.gtoper = '2' THEN ''
         ELSE 'gtoper non référencé' END ::character varying
      as publipost_prop_nom,
        case when proprietaire.gtoper = '1' THEN proprietaire.dprnus
         WHEN  proprietaire.gtoper = '2' THEN ''
         ELSE 'gtoper non référencé' END ::character varying
      as  publipost_prop_prenom,
      */
       case when proprietaire.gtoper = '1' THEN (coalesce(TRIM(proprietaire.dqualp),'') || ' ' || coalesce(TRIM(proprietaire.dnomus),'') || ' ' || coalesce(TRIM(proprietaire.dprnus),'')) 
         WHEN  proprietaire.gtoper = '2' THEN (coalesce(TRIM(proprietaire.dformjur),'') || ' ' || coalesce(TRIM(proprietaire.ddenom,'')))
         ELSE 'gtoper non référencé' END ::character varying
      as publipost_prop_nom ,  -- publipostage  : noms concaténés pour personnes physique et morales
      ltrim(proprietaire.dlign3,'0')::character varying(30) as publipost_prop_adresse1, -- afficher les adresse1 à 4 en publipostage 
      ltrim(proprietaire.dlign4,'0')::character varying(36) as publipost_prop_adresse2, -- afficher les adresse1 à 4 en publipostage
      proprietaire.dlign5 as publipost_prop_adresse3, -- afficher les adresse1 à 4 en publipostage
      proprietaire.dlign6 as publipost_prop_adresse4, -- afficher les adresse1 à 4 en publipostage

      

      
      st_pointonsurface(geo_parcelle.geom)::geometry(point,2154) as  geom_etiquette_position_point,  -- position de l'etiquette pour carte
      proprietaire.dnomlp   proprio_dnomlp    , -- Nom d’usage  [ EPTB ne plus utiliser] -
      proprietaire.dprnlp   proprio_dprnlp     -- Prénoms associés au nom d'usage [ EPTB ne plus utiliser]-
         from 
         $s$ || c_schemaname_cadastre|| $s$.geo_parcelle
         LEFT JOIN  $s$ || c_schemaname_cadastre|| $s$.$s$ || c_tablename_parcelle || $s$ parcelle ON (geo_parcelle.geo_parcelle= parcelle.parcelle)
         left join $s$ || c_schemaname_cadastre|| $s$.$s$ || c_tablename_proprio || $s$  proprietaire on (parcelle.comptecommunal=proprietaire.comptecommunal)
         LEFT JOIN  $s$ || c_schemaname_cadastre|| $s$.ccodro on  (proprietaire.ccodro = ccodro.ccodro)
         LEFT JOIN $s$ || c_schemaname_cadastre|| $s$.ccodem  on  (proprietaire.ccodem = ccodem.ccodem)
         LEFT JOIN $s$ || c_schemaname_cadastre|| $s$.commune  on  (parcelle.ccodep = commune.ccodep AND parcelle.ccocom = commune.ccocom )
         --LEFT JOIN cadastre_actuel.dformjur on  (proprietaire.dformjur = dformjur.dformjur)

         where st_intersects(geo_parcelle.geom,$s$ || QUOTE_LITERAL(ST_ASEWKT($1::geometry)) || $s$)
         AND ( proprietaire.gdesip = '1' OR  proprietaire.gdesip =  (CASE WHEN $s$ ||ins_is_seulement_destinataire_avis_impot ||  $s$ is true THEN '1' ELSE  '0' END )::character varying(1))

         order by parcelle.ccodep asc, commune.libcom asc, parcelle.ccosec asc, parcelle.dnupla asc

																



$s$ ;
																																																			-- indique le destinataire 
	


--RAISE NOTICE 'rq_find : %', string_sql::text;
FOR rq_find in EXECUTE string_sql LOOP 
	RETURN QUERY select 
					--true,	
	rq_find.geo_parcelle,
	rq_find.geom,
	rq_find.parc_jdatat,
	rq_find.parc_ccodep, 
	rq_find.parc_ccocom, 
	rq_find.parc_libcom ,
	rq_find.parc_ccosec, 
	rq_find.parc_dnupla,
	rq_find.parc_dnvoiri, 
	rq_find.parc_cconvo, 
	rq_find.parc_dvoilib, 
	rq_find.parc_dnupro, 
	rq_find.proprio_ccodro_lib,
	rq_find.proprio_ccodem_lib, 
	rq_find.proprio_gdesip, 
	rq_find.proprio_gtoper, 
	rq_find.proprio_dformjur, 
	rq_find.proprio_dqualp, 
	rq_find.proprio_ddenom, 
	rq_find.proprio_dnomus, 
	rq_find.proprio_dprnus, 
	rq_find.proprio_jdatnss, 
	rq_find.proprio_dldnss, 
	rq_find.proprio_epxnee, 
	rq_find.proprio_dnomcp, 
	rq_find.proprio_dprncp, 
	rq_find.proprio_dlign3, 
	rq_find.proprio_dlign4, 
	rq_find.proprio_dlign5, 
	rq_find.proprio_dlign6,
	rq_find.publipost_prop_nom,
	rq_find.publipost_prop_adresse1,
	rq_find.publipost_prop_adresse2,
	rq_find.publipost_prop_adresse3,
	rq_find.publipost_prop_adresse4,
	rq_find.geom_etiquette_position_point,

	rq_find.proprio_dnomlp, 
	rq_find.proprio_dprnlp
	;	
end loop;

END;
$BODY$
  LANGUAGE plpgsql STABLE STRICT
  COST 100
  ROWS 1000;
