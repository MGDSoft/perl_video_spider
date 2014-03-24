#! /usr/bin/env perl -w

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use POSIX;
use Time::Local;
use Term::ANSIColor qw(:constants);
use Data::Dumper;
use POSIX qw/strftime/;


$Data::Dumper::Indent = 0; 

my $DEBUG=1;
my $CORREO_AVISO='example@gmail.com';
my $PAGINA_DEFAULT="PAGINA_VARIABLE";
my $REGEX_YOUTUBE="youtube.com/(v\/|vi\/|watch\?v\=|embed\/)(.{11})";
my $REGEX_YOUTUBE_ACTIVE='alt="This video is unavailable"';

my $N_VIDEOS_POR_PAGINA=15;

my @ARR_DATOS=(
	{
		"url"=> "http://www.EXAMPLEEE"
		,"pagina_default" => "445"
		,"opc_subpaginas" => 0 			# el link esta dentro de otra página
		,"opc_busqueda_ultima_pag" => 1 	# busca la ultima pagina
		,"opc_pagina_ascendente" => 0 		# Las paginas tiene order de la query ASC en vez de DESC
		,"regex_busqueda_pagina_del_video" =>	''	# El video se encuentra en una pagina individual para el
		,"regex_busqueda_comentario" =>	'<div id="cuerpo_[0-9]+" class="cuerpo">(.*?)</div>' 
		,"regex_busqueda_ultima_pag" => '<strong class="paginas">.*?href="(.+?)" class="last">(.+?)</a>'
		,"activo" =>  1					# con esto cortas toda la actividad de esta página
		,"base_ref" =>  ""				# por si tiene la web rutas relativas
		,"bd_auto_insert" => 0				#insertar en la BD automaticamente 
		,"regex_busqueda_titulo" => ""
		,"regex_busqueda_descripcion" => ""
	},
	{
		"url"=> "http://www.EXAMPLEEE"
		,"pagina_default" => "1"
		,"opc_subpaginas" => 1 			# el link esta dentro de otra página
		,"opc_busqueda_ultima_pag" => 1 	# busca la ultima pagina
		,"opc_pagina_ascendente" => 0 		# Las paginas tiene order de la query ASC en vez de DESC
		,"regex_busqueda_pagina_del_video" =>	'<div class="fichaVideo">.*?<a href="(.+?)">'	# El video se encuentra en una pagina individual para el
		,"regex_busqueda_comentario" =>	'<div class="detallesVideo">(.+?)<div id="herramientas">'
		,"regex_busqueda_ultima_pag" => '<a class="arrowLeft" href="/categoria/deportes/p[0-9].html" title="p&aacute;gina anterior">&raquo;</a> <a href="/categoria/deportes/" title="p&aacute;gina ([0-9]+)">([0-9]+?)</a>'
		,"activo" => 0						# con esto cortas toda la actividad de esta página
		,"base_ref" =>  "http://www.EXAMPLEEE"	# por si tiene la web rutas relativas
		,"bd_auto_insert" => 1				#insertar en la BD automaticamente 
		,"regex_busqueda_titulo" => '<h2 id="tituloInterior">(.+?)</h2>'
		,"regex_busqueda_descripcion" => '<p class="descripcion">(.+?)<span class="fuente">'
	}
);


sub main
{
	titulo();
	limpia_ficheros();
	my ($contenido_html,$pagina_default)=('','');
	my (%item,@videos_nuevos,$i,$ultima_pagina_num,$cuenta_videos_tot);

	
	
	for my $item (@ARR_DATOS)
	{
		log_d((caller(0))[3].' empezamos con la página '.$item->{url});
		
		if ($item->{activo} ne 1)
		{
			next;
		}
			
		$pagina_default=replace_simple($item->{url},$PAGINA_DEFAULT,$item->{pagina_default});
		$contenido_html=buscamos_html_web($pagina_default);
		
		if ($item->{opc_busqueda_ultima_pag} eq 1)
		{
			$ultima_pagina_num = busqueda_ultima_pagina($contenido_html,$item->{regex_busqueda_ultima_pag});
		}else{
			$ultima_pagina_num = $PAGINA_DEFAULT;
		}
		
		# Buscando apartir de la nueva pagina
		$i=0;
		$cuenta_videos_tot=$#videos_nuevos;
		while ($#videos_nuevos < $N_VIDEOS_POR_PAGINA+$cuenta_videos_tot || $i eq $N_VIDEOS_POR_PAGINA+$cuenta_videos_tot)
		{
			$pagina_default=replace_simple($item->{url},$PAGINA_DEFAULT,$ultima_pagina_num);
			$contenido_html=buscamos_html_web($pagina_default);
			
			if ($item->{opc_subpaginas} eq 1)
			{
				busqueda_pagina_individual(\$contenido_html,\@videos_nuevos,$item); 
			}else{
				busqueda_you_tube(\$contenido_html,$item,\@videos_nuevos); 
			}
			
			log_i("Numero de videos totales ". $#videos_nuevos);
			$i++;
			
			if ($item->{opc_pagina_ascendente} eq 1)
			{
				$ultima_pagina_num++;
			}else{
				$ultima_pagina_num--;
			}
			
			if ($i > 20)
			{
				log_i("SALIDA POR QUE NO ENCUENTRA NADA");

				enviar_correo('Error Web-futbol '.$item->{url},'Error Web-futbol '.$item->{url});
				last;
			}
		}
	}
	
	if ($#videos_nuevos > 0)
	{
		log_o("Numero de videos totales ". $#videos_nuevos);	
	}else{
		log_e("Numero de videos totales ". $#videos_nuevos);
	}
	
	videos_mostrar_resultado(\@videos_nuevos);
	
}

sub enviar_correo
{

	open(MAIL, "|/usr/sbin/sendmail -t");

	my $title=shift;
	my $body=shift;
	my $subject=$title;
	my $to=$CORREO_AVISO;

	my $from= 'administracion@myequipo.com';

	 
	## Mail Header
	print MAIL "To: $to\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject\n\n";
	## Mail Body
	print MAIL $body;
	 
	close(MAIL);
}

sub videos_mostrar_resultado
{
	my @videos_nuevos=@{+shift};
	my ($json,$value,$i,$ii)=("","",0,0);
	$json="[";
	for my $href ( @videos_nuevos ) {		$json.= ($ii > 0) ? "," : "";
	    $json.= "{ ";
	    $i=0;
	    for my $role ( keys %$href ) {
		    $href->{$role} =~ s/(\")//g;
		    $href->{$role} =~ s/[\n\r\t]+//g;
		    $json.= ($i > 0) ? "," : "";
			$json.= "\"$role\" : \"$href->{$role}\"";
			$i++;
	    }
	    $json.= "}";
	    $ii++;
	}
	$json.= "]";
	log_resultado($json);
}


sub busqueda_pagina_individual
{
	my ($html,$videos_nuevos,$item)=(@_);
	my ($comentario,$url_pagina_indivi,%video_act,$contenido_individual_html);
	
	log_i ((caller(0))[3].$item->{regex_busqueda_pagina_del_video});
	
	
	while (${$html} =~ m{$item->{regex_busqueda_pagina_del_video}}sig) 
	{

		$url_pagina_indivi=$item->{base_ref}.$1;
		log_i("pagina individual del equipo ".$url_pagina_indivi);
		$contenido_individual_html=buscamos_html_web($url_pagina_indivi);
		busqueda_you_tube(\$contenido_individual_html,$item,\@{$videos_nuevos}); 
	}
	
}
sub comprobar_video_youtube_activo
{
	my $codigo=shift;
	my $content_html=buscamos_html_web("http://www.youtube.com/watch?v=$codigo");
	
	if ($content_html=~ m{$REGEX_YOUTUBE_ACTIVE}isg)
	{
		log_i((caller(0))[3]. " $codigo video inactivo");
		return 0;
	}else{
		return 1;
	}
	
}


sub busqueda_you_tube
{
	my ($html,$item,$videos_nuevos)=(@_);
	my ($comentario,$codigo_youtube,$video_url,%video_act,$titulo,$aux);
	log_d ((caller(0))[3]);
	while (${$html} =~ m{$item->{regex_busqueda_comentario}}sig) {
		$comentario=$1;
		$aux=$comentario;
		$titulo="";
		log_i ((caller(0))[3]. "detecto bloque comentarios");	
		if ($comentario  =~ m/$REGEX_YOUTUBE/ig)
		{
			log_i ((caller(0))[3]. "detecto link de youtube");
			$codigo_youtube=$2;
			
			if (comprobar_video_youtube_activo($codigo_youtube)==0)
			{
				next;
			}
			
			if ($item->{regex_busqueda_titulo} ne "")
			{
				if ($aux  =~ m{$item->{regex_busqueda_titulo}}isg)
				{
					$titulo=$1;
				}
			}
			if ($item->{regex_busqueda_descripcion} ne "")
			{
				
				if ($aux  =~ m{$item->{regex_busqueda_descripcion}}igs)
				{
					$comentario=$1;
				}
			}
			
			$video_url = "youtube.com/watch?v=$codigo_youtube";
			
			
			$comentario =~ s/<script.*?>.*?<\/script>//gs; # quitar javascript
			$comentario =~ s|<.+?>||g; #quitamos el codigo HTML  y dejamos solo el comentario
			
			push(@{$videos_nuevos},{"titulo" => $titulo, "comentarios" => $comentario,"comentarios" => $comentario, "url_youtube" => 'http://www.'.$video_url, "youtube_codigo" => $codigo_youtube, "BD_insert" => $item->{bd_auto_insert} , "base_ref" => $item->{url} });
			log_o ("Encontrado $video_url\n". '-' x 80, "\n");
		}
	}
	log_d("videos totales para esta página ".scalar  @{$videos_nuevos});
}

sub busqueda_ultima_pagina
{
	my $html = shift;
	my $param_busqueda = shift;
	
	log_d ((caller(0))[3]." buscando $param_busqueda");
	
	if ($html =~ m{$param_busqueda}sig )
	{
		my $ult_pag_num=$2;
		my $ult_pag_url=$1;
		log_d((caller(0))[3]." sí encuentra la ultima página $ult_pag_num");
		return $ult_pag_num;
		
	}else{
		log_e((caller(0))[3]." no encuentra la ultima página");
		return "";
	}
	
}

sub buscamos_html_web
{
	my $url = shift;
	my $json = shift;
	
	log_d ((caller(0))[3]." -> url: $url");
	my $ua = LWP::UserAgent->new;
	$ua->agent("Mozilla/4.76 [en] (Windows NT 5.0; U)");
	my $req; 
	if ($json)
	{
		$req = HTTP::Request->new(POST => $url);
		$req->header( 'Content-Type' => 'application/json' );
		$req->content( $json );
		
		#print  $json;
		
	}else{
		$req = HTTP::Request->new(GET => $url);
	}
	
	my $response = $ua->request($req);
	my $content = $response->content();
	return $content;
}

sub titulo {
	log_i("\n\n\n ------- INICIO DE EJECUCION --------- \n");
	
	
	#for my $href ( @ARR_DATOS ) {
	#    print "{ ";
	#    for my $role ( keys %$href ) {
	#		 print "\t$role => $href->{$role} \n";
	#    }
	#    print "},\n";
	#}
	
	#print "-----------------------------------\n\n\n";
	
}

sub replace_simple
{
	my $str_nombre = shift;
	my $text_busqueda = shift;
	my $text_remplaza = shift;
	
	
	$str_nombre =~ s/$text_busqueda/$text_remplaza/;
	
	return $str_nombre;
}

sub log_d {
	if ($DEBUG)
	{
		my $str = shift;
		print YELLOW,BLUE, "DEBUG - ". $str."\n",RESET;
	}
}
sub log_i {
	my $str = shift;
	if ($DEBUG)
	{
		print BOLD,BLUE, "INFO - ".$str."\n",RESET;
	}else{
		log_f(get_time()."INFO - ".$str);
	}
}
sub log_o {
	my $str = shift;
	if ($DEBUG)
	{
		print BOLD,GREEN, "OK - ".$str."\n",RESET;
	}else{
		log_f(get_time()."OK - ".$str);
	}
}
sub log_e {
	my $str = shift;
	
	if ($DEBUG)
	{
		print BOLD,RED, "ERROR - ".$str."\n",RESET;
	}else{
		log_f(get_time()."ERROR - ".$str);
	}
}
sub limpia_ficheros{
	unlink('results/roba_resultado.txt');
	unlink('results/log_roba.txt');
}
sub log_resultado{
	my $str = shift;
	
	open(FILEHANDLE, "> results/roba_resultado.txt") or die 'cannot open file!';  
	print FILEHANDLE $str;
	 
	# close file handle
	close(FILEHANDLE);
}

sub log_f{
	my $str = shift;
	
	open(FILEHANDLE, ">> results/log_roba.txt") or die 'cannot open file!';  

	print FILEHANDLE $str;
	 
	# close file handle
	close(FILEHANDLE);
}

sub get_time()
{
	return strftime('%D %T - ',localtime);
}

main();
