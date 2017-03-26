//////////////////////////////////////////////////////////
//Sketch modificado y traducido por Alex TC (TCRobotics)//
//Para BricoGeek.com                                    // 
//web: http://tcrobotics.blogspot.com                   //
//twitter: @TCRobotics                                  //
//email: alex.tc.robotics-AT-gmail.com                  //
//////////////////////////////////////////////////////////

// Ladyada's logger modified by Bill Greiman to use the SdFat library 
// this is a generic logger that does checksum testing so the data written should be always good
// Assumes a sirf III chipset logger attached to pin 0 and 1

uint8_t sensorCount = 1; //numero de sensores analogicos a loguear

// Librerias para la SD
#include <SdFat.h>
#include <SdFatUtil.h>
#include <avr/pgmspace.h>

#define isdigit(x) ( x >= '0' && x <= '9')

//extern uint16_t _end;

Sd2Card card;
SdVolume volume;
SdFile root;
SdFile f;

#define led1Pin 2          // LED de estado en el pin 7
 

#define BUFFSIZE 73         // se mete en el buffer una sentencia NMEA cada vez, 73bytes es mas grande que la longitud maxima
char buffer[BUFFSIZE];      
char buffer2[12];

uint8_t bufferidx = 0;
uint32_t tmp;

//////////////CONFIGURACION DEL MODULO GPS (VER MANUAL DE REFERENCIA NMEA)///////////////////////////
#define LOG_RMC  1      // Datos de localizacion esenciales RMC
#define RMC_ON   "$PSRF103,4,0,1,1*21\r\n"  // Comando que se manda para activar RMC (1 hz)
#define RMC_OFF  "$PSRF103,4,0,0,1*20\r\n"  // Comando que se manda para desactivar RMC

#define LOG_GGA  0      // contains fix, hdop & vdop data
#define GGA_ON   "$PSRF103,0,0,1,1*25\r\n"   // Comando que se manda para activar GCA (1 hz)
#define GGA_OFF  "$PSRF103,0,0,0,1*24\r\n"   // Comando que se manda para desactivar GGA

#define LOG_GSA 0      // satellite data
#define GSA_ON   "$PSRF103,2,0,1,1*27\r\n"   // Comando que se manda para activar GSA (1 hz)
#define GSA_OFF  "$PSRF103,2,0,0,1*26\r\n"   // Comando que se manda para desactivar GSA

#define LOG_GSV  0      // detailed satellite data
#define GSV_ON   "$PSRF103,3,0,1,1*26\r\n"  // Comando que se manda para activar GSV (1 hz)
#define GSV_OFF  "$PSRF103,3,0,0,1*27\r\n"  // Comando que se manda para desactivar GSV

#define LOG_GLL 0      // Loran-compatibility 

#define USE_WAAS   1     // Util para conseguir mas precision, pero mas lento y consume mas bateria
#define WAAS_ON    "$PSRF151,1*3F\r\n"       // Comando que se manda para activar WAAS
#define WAAS_OFF   "$PSRF151,0*3E\r\n"       // Comando que se manda para desactivar WAAS

#define LOG_RMC_FIXONLY 1  // loguear solo cuando tenemos la posicion fijada en el RMC?
uint8_t fix = 0; // dato actual de fijacion de posicion
//////////////////////////////////////////////////////////////////////////////////////////////////////
// macros to use PSTR
#define putstring(str) SerialPrint_P(PSTR(str))
#define putstring_nl(str) SerialPrintln_P(PSTR(str))

// lee un valor hexadecimal y devuelve su valor decimal
uint8_t parseHex(char c) {
    if (c < '0')  return 0;
    if (c <= '9') return c - '0';
    if (c < 'A')  return 0;
    if (c <= 'F') return (c - 'A')+10;
}

uint8_t i;

// Parpadea el LED si hay un error
void error(uint8_t errno) {
  if (card.errorCode()) {
    putstring("Error en la SD: ");
    Serial.print(card.errorCode(), HEX);
    Serial.print(',');
    Serial.println(card.errorData(), HEX);
  }
   while(1) {
     for (i=0; i<errno; i++) {    
       digitalWrite(led1Pin, HIGH);
       Serial.println("error");
       delay(100);
       digitalWrite(led1Pin, LOW);     
       delay(100);
     }
     for (; i<10; i++) {
       delay(200);
     }      
   } 
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void setup()
{
  Serial.begin(4800);  //a esta frecuencia funciona el GPS
  pinMode(10, OUTPUT); //esencial para que funcione la microSD shield !!!
  putstring_nl("GPSlogger BricoGeek");
  pinMode(led1Pin, OUTPUT);      // sets the digital pin as output
   pinMode(13, OUTPUT); 
  if (!card.init()) {
    putstring_nl("La inicializacion de la SD ha fallado!"); 
    error(1);
  }
  if (!volume.init(card)) {
    putstring_nl("No hay particion!"); 
    error(2);
  }
  if (!root.openRoot(volume)) {
        putstring_nl("No se puede abrir el directorio raiz"); 
    error(3);
  }
  strcpy(buffer, "GPSLOG00.CSV"); //empezara a escribir en 00, si ya hay un archivo previo incrementa la cuenta
  for (i = 0; i < 100; i++) {
    buffer[6] = '0' + i/10;
    buffer[7] = '0' + i%10;
    if (f.open(root, buffer, O_CREAT | O_EXCL | O_WRITE)) break;
  }
  
  if(!f.isOpen()) {
    putstring("No se ha podido crear "); Serial.println(buffer);
    error(3);
  }
  putstring("escribiendo en "); Serial.println(buffer);
  putstring_nl("Preparado!");

  // escritura de la cabecera
  if (sensorCount > 6) sensorCount = 6;
  strncpy_P(buffer, PSTR("time,lat,long,speed,date,sens0,sens1,sens2,sens3,sens4,sens5"), 24 + 6*sensorCount);
  Serial.println(buffer);
  // clear print error
  f.writeError = 0;
  f.println(buffer);
  if (f.writeError || !f.sync()) {
    putstring_nl("no se pudo escribir la cabecera!");
    error(5);
  }
  
  delay(1000);
//Aqui se hace la configuracion del gps que definimos mas arriba
   putstring("\r\n");
#if USE_WAAS == 1 
   putstring(WAAS_ON); // on WAAS
#else
  putstring(WAAS_OFF); // on WAAS
#endif

#if LOG_RMC == 1
  putstring(RMC_ON); // on RMC
#else
  putstring(RMC_OFF); // off RMC
#endif

#if LOG_GSV == 1 
  putstring(GSV_ON); // on GSV
#else
  putstring(GSV_OFF); // off GSV
#endif

#if LOG_GSA == 1
  putstring(GSA_ON); // on GSA
#else
  putstring(GSA_OFF); // off GSA
#endif

#if LOG_GGA == 1
 putstring(GGA_ON); // on GGA
#else
 putstring(GGA_OFF); // off GGA
#endif
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void loop()                     
{
  //Serial.println(Serial.available(), DEC);
  char c;
  uint8_t sum;
  
  // lee una linea NMEA del GPS
  if (Serial.available()) {
    c = Serial.read();
    //Serial.print(c, BYTE);
    if (bufferidx == 0) {
      while (c != '$')
        c = Serial.read(); // espera que nos llegue un $
    }
    buffer[bufferidx] = c;

    //Serial.print(c, BYTE);
    if (c == '\n') {
      //putstring_nl("EOL");
      //Serial.print(buffer);
      buffer[bufferidx+1] = 0; // termina
     
      if (buffer[bufferidx-4] != '*') {
        // no hay checksum?
        Serial.print('*', BYTE);
        bufferidx = 0;
        return;
      }
      // calcula checksum
      sum = parseHex(buffer[bufferidx-3]) * 16;
      sum += parseHex(buffer[bufferidx-2]);
      
      // comprueba checksum 
      for (i=1; i < (bufferidx-4); i++) {
        sum ^= buffer[i];
      }
      if (sum != 0) {
        //putstring_nl("error de checksum");
        Serial.print('~', BYTE);
        bufferidx = 0;
        return;
      }
      // tenemos datos!
      //Serial.println(buffer);
      if (strstr(buffer, "GPRMC")) {
        // buscamos si tenemos la posicion fijada
        char *p = buffer;
        p = strchr(p, ',')+1;
        p = strchr(p, ',')+1;       // vamos a el tercer dato
        
        if (p[0] == 'V') {
          digitalWrite(led1Pin, LOW);  // no tenemos fijada la posicion
          fix = 0;
        } 
        else {
          digitalWrite(led1Pin, HIGH); // tenemos fijada la posicion
          fix = 1;
        }
      }

#if LOG_RMC_FIXONLY
      if (!fix) {
          Serial.print('_', BYTE); //aqui esperamos si lo hemos configurado para que solo coja datos con la posicion fijada
          bufferidx = 0;
          return;
      } 
#endif
      
      Serial.println();
      Serial.print("Secuencia NMEA recibida: ");
      Serial.print(buffer);
  
      // buscando los datos
      // encuentra el tiempo
      char *p = buffer;
      p = strchr(p, ',')+1;
      buffer[0] = p[0];
      buffer[1] = p[1];
      buffer[2] = ':';
      buffer[3] = p[2];
      buffer[4] = p[3];
      buffer[5] = ':';
      buffer[6] = p[4];
      buffer[7] = p[5];
      // ignoramos milisegundos
      buffer[8] = ',';
      
      p = strchr(buffer+8, ',')+1;

      p = strchr(p, ',')+1;
      // encuentra latitud
      p = strchr(p, ',')+1;

      buffer[9] = '+';
      buffer[10] = p[0];
      buffer[11] = p[1];
      buffer[12] = ' ';
      strncpy(buffer+13, p+2, 7);
      buffer[20] = ',';
      
      p = strchr(buffer+21, ',')+1;
      if (p[0] == 'S')
        buffer[9] = '-';
      
      // encuentra longitud
      p = strchr(p, ',')+1;
      buffer[21] = '+';
      buffer[22] = p[0];
      buffer[23] = p[1];
      buffer[24] = p[2];
      buffer[25] = ' ';
      strncpy(buffer+26, p+3, 7);
      buffer[33] = ',';
      
      p = strchr(buffer+34, ',')+1;
      if (p[0] == 'W')
        buffer[21] = '-';
      
      // encuentra velocidad
      p = strchr(p, ',')+1;
      tmp = 0;
      if (p[0] != ',') {
        // convertimos la velocidad (viene en nudos)
        while (p[0] != '.' && p[0] != ',') {
          tmp *= 10;
          tmp += p[0] - '0';
          p++;       
        }
        tmp *= 10;
        if (isdigit(p[1])) 
          tmp += p[1] - '0';
        tmp *= 10;
        if (isdigit(p[2])) 
        tmp += p[2] - '0';

        tmp *= 185; //la convertimos en km/h


      } 
      tmp /= 100;
      
      buffer[34] = (tmp / 10000) + '0';
      tmp %= 10000;
      buffer[35] = (tmp / 1000) + '0';
      tmp %= 1000;
      buffer[36] = (tmp / 100) + '0';
      tmp %= 100;
      buffer[37] = '.';
      buffer[38] = (tmp / 10) + '0';
      tmp %= 10;
      buffer[39] = tmp + '0';
       
      buffer[40] = ',';
      p = strchr(p, ',')+1;
      // skip past bearing
      p = strchr(p, ',')+1;
      //mod para evitar problemas cuando falta algun dato (bill greiman)
      uint8_t date[6];
      for (uint8_t id = 0; id < 6; id++) date[id] = p[id];
      // formatea la fecha asi 2001-01-31
      buffer[41] = '2';
      buffer[42] = '0';  // en el año 2100 esto no funcionara XD
      buffer[43] = date[4];
      buffer[44] = date[5];
      buffer[45] = '-';
      buffer[46] = date[2];
      buffer[47] = date[3];
      buffer[48] = '-';
      buffer[49] = date[0];
      buffer[50] = date[1];
      buffer[51] = 0;
 
      if(f.write((uint8_t *) buffer, 51) != 51) {
         putstring_nl("no se ha podido escribir fix!");
	       return;
      }
      Serial.print("Datos escritos en la SD: ");
      Serial.print(buffer);
      
      f.writeError = 0;      
///////////////////////////////////////////////AQUI SE AÑADE LA INFORMACION DE LOS SENSORES///////////////////////////////////////////////////////////////////////////////////////////////////////////////
      for (uint8_t ia = 0; ia < sensorCount; ia++) {
        Serial.print(',');   //escribimos por serie
        f.print(',');        //escribimos en el archivo
        uint16_t data = analogRead(ia);
        Serial.print(data);  //escribimos por serie
        f.print(data);       //escribimos en el archivo
      }
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////      
      
      Serial.println();
      f.println();
      if (f.writeError || !f.sync()) {
         putstring_nl("no se ha podido escribir el dato!");
         error(4);
      }
      bufferidx = 0;
      return;
    }
    bufferidx++;
    if (bufferidx == BUFFSIZE-1) {
       Serial.print('!', BYTE);
       bufferidx = 0;
    }
  }
}

