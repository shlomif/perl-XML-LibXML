/* $Id$ */
#include <libxml/tree.h>
#include <libxml/encoding.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xmlIO.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include <stdio.h>

xmlDocPtr
domCreateDocument( xmlChar *version, xmlChar *enc ){
    xmlDocPtr doc = NULL;
    doc = xmlNewDoc( version );  
    doc->charset  = XML_CHAR_ENCODING_UTF8;
    if ( enc != NULL && *enc!= 0 ) {
      /* if an encoding is passed, we will assume UTF8, otherwise we set 
       * the passed encoding 
       */
        doc->encoding = xmlStrdup(enc);
    }
    else {
        doc->encoding = xmlStrdup("UTF-8");
    }

    return doc;
}

/**
 * Name: domReadWellBalancedString
 * Synopsis: xmlNodePtr domReadWellBalancedString( xmlDocPtr doc, xmlChar *string )
 * @doc: the document, the string should belong to
 * @string: the string to parse
 *
 * this function is pretty neat, since you can read in well balanced 
 * strings and get a list of nodes, which can be added to any other node.
 * (shure - this should return a doucment_fragment, but still it doesn't)
 *
 * the code is pretty heavy i think, but deep in my heard i believe it's 
 * worth it :) (e.g. if you like to read a chunk of well-balanced code 
 * from a databasefield)
 *
 * in 99% the cases i believe it is faster than to create the dom by hand,
 * and skip the parsing job which has to be done here.
 **/
xmlNodePtr 
domReadWellBalancedString( xmlDocPtr doc, xmlChar* block ) {
    int retCode       = -1;
    xmlNodePtr helper = NULL;
    xmlNodePtr nodes  = NULL;
    
    if ( block ) {
        /* read and encode the chunk */
        retCode = xmlParseBalancedChunkMemory( doc, 
                                               NULL,
                                               NULL,
                                               0,
                                               block,
                                               &nodes );

        /* error handling */
        if ( retCode != 0 ) {
            /* if the code was not well balanced, we will not return 
             * a bad node list, but we have to free the nodes */
            while( nodes != NULL ) {
                helper = nodes->next;
                xmlFreeNode( nodes );
                nodes = helper;
            }
        }
    }

    return nodes;
}

/** 
 * encodeString returns an UTF-8 encoded String
 * while the encodig has the name of the encoding of string
 **/ 
xmlChar*
domEncodeString( const char *encoding, const char *string ){
    xmlCharEncoding enc;
    xmlChar *ret = NULL;
    
    if ( string != NULL ) {
        if( encoding != NULL ) {
            enc = xmlParseCharEncoding( encoding );
            if ( enc > 0 ) {
                if( enc > 1 ) {
                    xmlBufferPtr in, out;
                    xmlCharEncodingHandlerPtr coder ;
                    in  = xmlBufferCreate();
                    out = xmlBufferCreate();
                    
                    coder = xmlGetCharEncodingHandler( enc );
                    
                    xmlBufferCCat( in, string );
                    
                    if ( xmlCharEncInFunc( coder, out, in ) >= 0 ) {
                        ret = xmlStrdup( out->content );
                    }
                    else {
                        /* printf("encoding error\n"); */
                    }
                    
                    xmlBufferFree( in );
                    xmlBufferFree( out );
                }
                else {
                    /* if utf-8 is requested we do nothing */
                    ret = xmlStrdup( string );
                }
            }
            else {
                /* printf( "encoding error: no enciding\n" ); */
            }
        }
        else {
            /* if utf-8 is requested we do nothing */
            ret = xmlStrdup( string );
        }
    }
    return ret;
}

/**
 * decodeString returns an $encoding encoded string.
 * while string is an UTF-8 encoded string and 
 * encoding is the coding name
 **/
char*
domDecodeString( const char *encoding, const xmlChar *string){
    char *ret=NULL;
    xmlBufferPtr in, out;
    
    if ( string != NULL ) {
        if( encoding != NULL ) {
            xmlCharEncoding enc = xmlParseCharEncoding( encoding );
            /*      printf("encoding: %d\n", enc ); */
            if ( enc > 0 ) {
                if( enc > 1 ) {
                    xmlBufferPtr in, out;
                    xmlCharEncodingHandlerPtr coder;
                    in  = xmlBufferCreate();
                    out = xmlBufferCreate();
                    
                    coder = xmlGetCharEncodingHandler( enc );
                    xmlBufferCat( in, string );        
                    
                    if ( xmlCharEncOutFunc( coder, out, in ) >= 0 ) {
                        ret=xmlStrdup(out->content);
                    }
                    else {
                        /* printf("decoding error \n"); */
                    }
                    
                    xmlBufferFree( in );
                    xmlBufferFree( out );
                }
                else {
                    ret = xmlStrdup(string);
                }
            }
            else {
                /* warn( "decoding error:no encoding\n" ); */
                ret = xmlStrdup( string );
            }
        }
        else {
            /* if utf-8 is requested we do nothing */
            ret = xmlStrdup( string );
        }
    }
    return ret;
}

/** 
 * internal helper: insert node to nodelist
 * synopsis: xmlNodePtr insert_node_to_nodelist( leader, insertnode, followup );
 * while leader and followup are allready list nodes. both may be NULL
 * if leader is null the parents children will be reset
 * if followup is null the parent last will be reset.
 * leader and followup has to be followups in the nodelist!!!
 * the function returns the node inserted. if a fragment was inserted,
 * the first node of the list will returned
 *
 * i ran into a misconception here. there should be a normalization function
 * for the DOM, so sequences of text nodes can get replaced by a single 
 * text node. as i see DOM Level 1 does not allow text node sequences, while
 * Level 2 and 3 do.
 **/
xmlNodePtr 
insert_node_to_nodelist( xmlNodePtr lead, xmlNodePtr node, xmlNodePtr follow ){
    xmlNodePtr cld1, cld2, par;
    if( node == NULL ) {
        return;
    }

    cld1 = node;
    cld2 = node;
    par = NULL;

    if( lead != NULL ) {
        par = lead->parent;
    }
    else if( follow != NULL ) {
        par = follow->parent;
    }

    if( node->type == XML_DOCUMENT_FRAG_NODE ) {
        xmlNodePtr hn = node->children;
        
        cld1 = node->children;
        cld2 = node->last;
        node->last = node->children = NULL;

        while ( hn ) {
            hn->parent = par;
            hn = hn->next;
        }
    }
  

    if( cld1 != NULL && cld2 != NULL && par != NULL ) {
        cld1->parent = par;
        cld2->parent = par;
   
        if ( lead == NULL ) {
            par->children = cld1;
        }
        else {
            lead->next = cld1;
            cld1->prev  = lead;
        }
  
        if ( follow == NULL ){
            par->last = cld2;
        } 
        else {
            follow->prev = cld2;
            cld2->next  = follow;
        }
    }

    return cld1;
}

xmlNodePtr
domUnbindNode( xmlNodePtr );

xmlNodePtr
domSetOwnerDocument( xmlNodePtr self, xmlDocPtr newDoc );

xmlNodePtr
domIsNotParentOf( xmlNodePtr node1, xmlNodePtr node2 );

xmlNodePtr
domImportNode( xmlDocPtr doc, xmlNodePtr node, int move );

xmlNodePtr
domRemoveChild( xmlNodePtr self, xmlNodePtr old );

/**
 * Name: domName
 * Synopsis: string = domName( node );
 *
 * domName returns the full name for the current node.
 * If the node belongs to a namespace it returns the prefix and 
 * the local name. otherwise only the local name is returned.
 **/
xmlChar*
domName(xmlNodePtr node) {
    xmlChar *qname = NULL; 
    if ( node ) {
        if (node->ns != NULL && node->ns->prefix != NULL) {
            xmlChar *tname = xmlStrdup( node->ns->prefix );
            tname = xmlStrcat( tname , ":" );
            tname = xmlStrcat( tname , node->name );
            qname = tname;
        } 
        else {
            qname = xmlStrdup( node->name );
        }
    }

    return qname;
}

void
domSetName( xmlNodePtr node, char* name ) {
    xmlChar* str = NULL;  
    /* TODO: add ns support */
    if ( node == NULL || name == NULL ) 
        return ;
    if ( node->name != NULL ) {
        /* required since node->name is const! */
        xmlFree( (void*) node->name );
    }

    node->name = xmlStrdup( name );
}

/**
 * Name: domAppendChild
 * Synopsis: xmlNodePtr domAppendChild( xmlNodePtr par, xmlNodePtr newCld );
 * @par: the node to append to
 * @newCld: the node to append
 *
 * Returns newCld on success otherwise NULL
 * The function will unbind newCld first if nesseccary. As well the 
 * function will fail, if par or newCld is a Attribute Node OR if newCld 
 * is a parent of par. 
 * 
 * If newCld belongs to a different DOM the node will be imported 
 * implicit before it gets appended. 
 **/
xmlNodePtr
domAppendChild( xmlNodePtr self,
                xmlNodePtr newChild ){
    /* unbinds the new node if nessecary ... does not handle attributes :P */
    /* fprintf( stderr,"check if child is not parent of the current node\n"); */
    newChild = domIsNotParentOf( newChild, self );

    if ( self == NULL ) {
        return newChild;
    }

    if ( newChild == NULL
         || newChild->type == XML_ATTRIBUTE_NODE
         || self->type == XML_ATTRIBUTE_NODE
         || ( newChild->type == XML_DOCUMENT_FRAG_NODE 
              && newChild->children == NULL ) 
         ){
        /* HIERARCHIY_REQUEST_ERR */
        /* fprintf(stderr,"HIERARCHIY_REQUEST_ERR\n"); */
        return NULL;
    }

    if ( newChild->doc == self->doc ){
        /* fprintf(stderr,"child part of the current dom\n"); */
        newChild= domUnbindNode( newChild );
    }
    else {
        /* WRONG_DOCUMENT_ERR - non conform implementation*/
        /* fprintf(stderr,"WRONG_DOCUMENT_ERR - non conform implementation\n"); */
        newChild= domImportNode( self->doc, newChild, 1 );
        /* fprintf(stderr,"post import\n");  */

    }
 
    /* fprintf(stderr,"real append\n");  */
    if ( self->children != NULL ) {
        /* fprintf(stderr,"append to the end of the child list\n");  */
        newChild = insert_node_to_nodelist( self->last, newChild , NULL );
    }
    else if (newChild->type == XML_DOCUMENT_FRAG_NODE ) {
        xmlNodePtr cld = newChild->children;
        /* fprintf(stderr," insert a fragment into an empty node\n");  */
        self->children = newChild->children;
        self->last     = newChild->last;
        while( cld != NULL ){
            cld->parent = self;
            cld = cld->next;
        }
        /* cld->parent = self; */
        
        newChild->children = NULL;
        newChild->last = NULL;
        /* cld = self->children; */
    }
    else {
        /* fprintf(stderr,"single node, no children\n");  */

        self->children = newChild;
        self->last     = newChild;
        newChild->parent= self;
    }
    
    /* fprintf(stderr,"append done...\n");  */
    return newChild;
}


xmlNodePtr
domReplaceChild( xmlNodePtr self, xmlNodePtr new, xmlNodePtr old ) {
    if ( self== NULL ){
        return NULL;
    }
    if ( new == NULL ) {
        /* level2 sais nothing about this case :( */
        return domRemoveChild( self, old );
    }

    /* handle the different node types */
    switch( new->type ) {
    case XML_ATTRIBUTE_NODE:
        return NULL;
        break;
    default:
        break;
    }
    
    if( ( old != NULL 
          && ( old->type == XML_ATTRIBUTE_NODE 
               || old->type == XML_DOCUMENT_FRAG_NODE 
               || old->parent != self ) )
        || self->type== XML_ATTRIBUTE_NODE
        || domIsNotParentOf( new, self ) == NULL 
        || ( new->type == XML_DOCUMENT_FRAG_NODE && new->children == NULL ) ) { 
        
        /* HIERARCHY_REQUEST_ERR */
        return NULL;
    }
    
    if ( new == old ) {
        /* dom level 2 throws no exception if new and old are equal */
        return new;
    }

    if ( old == NULL ) {
        domAppendChild( self, new );
        return old;
    }

    if ( new->doc == self->doc ) {
      new = domUnbindNode( new ) ;
    }
    else {
        /* WRONG_DOCUMENT_ERR - non conform implementation */
        new = domImportNode( self->doc, new, 1 );
    }
    
    if( old == self->children && old == self->last ) {
        domRemoveChild( self, old );
        domAppendChild( self, new );
    }
    else {
        insert_node_to_nodelist( old->prev, new, old->next );
        old->parent = NULL;
        old->next   = NULL;
        old->prev   = NULL;    
    }

    return old;
}

xmlNodePtr
domRemoveChild( xmlNodePtr self, xmlNodePtr old ) {
    if ( (self != NULL)  
         && (old!=NULL) 
         && (self == old->parent )
         && (old->type != XML_ATTRIBUTE_NODE) 
         ) {
        old = domUnbindNode( old );
    }
    return old ;
}

xmlNodePtr
domInsertBefore( xmlNodePtr self, 
                 xmlNodePtr newChild,
                 xmlNodePtr refChild ){

    if ( self == NULL || newChild == NULL ) {
        return NULL;
    }

    if ( newChild != NULL && domIsNotParentOf( newChild, self ) == NULL ){
        /* HIERARCHIY_REQUEST_ERR */
        return NULL;
    }

    if ( refChild == newChild ) {
        return newChild;
    }
    if( ( refChild != NULL 
          && ( refChild->type == XML_ATTRIBUTE_NODE 
               || refChild->type == XML_DOCUMENT_FRAG_NODE ) )
        || ( newChild != NULL && ( newChild->type == XML_ATTRIBUTE_NODE
                                   || ( newChild->type==XML_DOCUMENT_FRAG_NODE 
                                        && newChild->children == NULL ) ) ) ) {
        /* HIERARCHY_REQUEST_ERR */
        /* this condition is true, because:
         * case 1: if the reference is an attribute, it's not a child
         * case 2: if the reference is a document_fragment, it's not part of the tree
         * case 3: if the newchild is an attribute, it can't get inserted as a child
         * case 4: if newchild is a document fragment and has no children, we can't
         *         insert it
         */
        return NULL;
    }

    if ( self->doc == newChild->doc ){
        newChild = domUnbindNode( newChild );
    }
    else {
        newChild = domImportNode( self->doc, newChild, 1 );
    }

    if ( refChild == NULL ) {
        if( self->children == NULL ){
            newChild = domAppendChild( self, newChild );
        } 
        else {
            newChild = insert_node_to_nodelist( NULL, newChild, self->children );
        }
    }

    if ( self == refChild->parent ) {
        newChild = insert_node_to_nodelist( refChild->prev, newChild, refChild );
    }
    else {
        newChild = NULL;
    }

    return newChild;
}

xmlNodePtr
domInsertAfter( xmlNodePtr self, 
                xmlNodePtr newChild,
                xmlNodePtr refChild ){
    if ( self == NULL ) {
        return NULL;
    }
  
    newChild = domIsNotParentOf( newChild, self );

    if ( refChild == newChild ) {
        return newChild;
    }

    if ( refChild == NULL ) {
        return domAppendChild( self, newChild );
    }

    if( refChild->type == XML_ATTRIBUTE_NODE 
        || refChild->type == XML_DOCUMENT_FRAG_NODE
        || ( newChild != NULL && ( newChild->type == XML_ATTRIBUTE_NODE
                                   || ( newChild->type==XML_DOCUMENT_FRAG_NODE 
                                        && newChild->children == NULL ) ) ) ) {
        /* HIERARCHY_REQUEST_ERR */
        return NULL;
    }

    if ( newChild != NULL && 
         self == refChild->parent &&
         refChild != newChild ) {
        
        if( newChild->doc == self->doc ) {
            domUnbindNode( newChild );
        }
        else {
            domImportNode( self->doc, newChild, 1 );
        }

        newChild = insert_node_to_nodelist( refChild, newChild, refChild->next );
    }
    else {
        newChild = NULL;
    }
    return newChild;
}

xmlNodePtr
domReplaceNode( xmlNodePtr oldnode, xmlNodePtr newnode ){
    xmlNodePtr prev, next, par;
    if ( oldnode != NULL ) {
        if( newnode == NULL ) {
            domUnbindNode( oldnode );
        }
        else {
            par  = oldnode->parent;
            prev = oldnode->prev;
            next = oldnode->next;
            domUnbindNode( oldnode );
            if( prev == NULL && next == NULL ) {
                domAppendChild( par ,newnode ); 
            }
            else {
                insert_node_to_nodelist( prev, newnode, next );
            }
        }
    }
    return oldnode;
}

void
domSetNodeValue( xmlNodePtr n , xmlChar* val ){
    if ( n == NULL ) 
        return;
    if ( val == NULL ){
        val = "";
    }
  
    if( n->type == XML_ATTRIBUTE_NODE ){
        if ( n->children != NULL ) {
            n->last = NULL;
            xmlFreeNodeList( n->children );
        }
        n->children = xmlNewText( val );
        n->children->parent = n;
        n->children->doc = n->doc;
        n->last = n->children; 
    }
    else if( n->content != NULL ) {
        /* free old content */
        xmlFree( n->content );
        n->content = xmlStrdup(val);   
    }
}


void
domSetParentNode( xmlNodePtr self, xmlNodePtr p ) {
    /* never set the parent to a node in the own subtree */ 
    self = domIsNotParentOf( self, p );
    if( self != NULL ){
        if( self->parent != p ){
            domUnbindNode( self );
            self->parent = p;
            if( p->doc != self->doc ) {
                self->doc = p->doc;
            }
        }
    }
}

xmlNodePtr
domUnbindNode( xmlNodePtr self ) {
    if ( (self != NULL) && (self->parent != NULL) ) { 
        if( self->parent!=NULL ) {
            if( self->parent->properties == (xmlAttrPtr) self ) 
                self->parent->properties = (xmlAttrPtr)self->next;
            if ( self == self->parent->last ) 
                self->parent->last = self->prev;
            if ( self == self->parent->children ) 
                self->parent->children = self->next;
        }
        if ( self->next != NULL )
            self->next->prev = self->prev;
        if ( self->prev != NULL )
            self->prev->next = self->next;
        
        self->parent = NULL;
        self->next   = NULL;
        self->prev   = NULL;
    }
    return self;
}

/**
 * donIsNotParentOf tests, if node1 is parent of node2. this test is very
 * important to avoid circular constructs in trees. if node1 is NOT parent
 * of node2 the function returns node1, otherwise NULL.
 **/
xmlNodePtr
domIsNotParentOf( xmlNodePtr node1, xmlNodePtr node2 ) {
    xmlNodePtr helper = NULL;

    if ( node1 == NULL ) {
        return NULL;
    }
    
    if( node2 == NULL || node1->doc != node2->doc) {
        return node1;
    }
    if( node2->type == XML_DOCUMENT_NODE ){  
      return node1;
    }
    
    helper= node2;
    while ( helper!=NULL ) {
        if( helper == node1 ) {
            return NULL;
        }
        
        helper = helper->parent;
        if ( (xmlDocPtr) helper == node2->doc ) {
            helper = NULL;
        }
    }
    
    return node1;
}

/**
 * this is a wrapper function that does the type evaluation for the 
 * node. this makes the code a little more readable in the .XS
 * 
 * the code is not really portable, but i think we'll avoid some 
 * memory leak problems that way.
 **/

const char*
domNodeTypeName( xmlNodePtr elem ){
    const char *name = "XML::LibXML::Node";

    if ( elem != NULL ) {
        char * ptrHlp;
        switch ( elem->type ) {
        case XML_ELEMENT_NODE:
            name = "XML::LibXML::Element";   
            break;
        case XML_TEXT_NODE:
            name = "XML::LibXML::Text";
            break;
        case XML_COMMENT_NODE:
            name = "XML::LibXML::Comment";
            break;
        case XML_CDATA_SECTION_NODE:
            name = "XML::LibXML::CDATASection";
            break;
        case XML_ATTRIBUTE_NODE:
            name = "XML::LibXML::Attr"; 
            break;
        case XML_DOCUMENT_NODE:
            name = "XML::LibXML::Document";
            break;
        case XML_DOCUMENT_FRAG_NODE:
            name = "XML::LibXML::DocumentFragment";
            break;
        case XML_NAMESPACE_DECL:
            name = "XML::LibXML::Namespace";
            break;
        case XML_DTD_NODE:
            name = "XML::LibXML::Dtd";
            break;
        case XML_PI_NODE:
            name = "XML::LibXML::PI";
            break;
        default:
            name = "XML::LibXML::Node";
            break;
        };
        return name;
    }

    return "";
}

xmlNodePtr
domCreateCDATASection( xmlDocPtr self , xmlChar * strNodeContent ){
    xmlNodePtr elem = NULL;

    if ( ( self != NULL ) && ( strNodeContent != NULL ) ) {
        elem = xmlNewCDataBlock( self, strNodeContent, xmlStrlen(strNodeContent) );
        elem->next = NULL;
        elem->prev = NULL;
        elem->children = NULL ;
        elem->last = NULL;
        elem->doc = self->doc;   
    }

    return elem;
}


xmlNodePtr 
domDocumentElement( xmlDocPtr doc ) {
    xmlNodePtr cld=NULL;
    if ( doc != NULL && doc->doc != NULL && doc->doc->children != NULL ) {
        cld= doc->doc->children;
        while ( cld != NULL && cld->type != XML_ELEMENT_NODE ) 
            cld= cld->next;
  
    }
    return cld;
}

/**
 * setDocumentElement:
 * @doc: the document
 * @newRoot: the new rootnode
 *
 * a document can have only ONE root node, so this function searches
 * the first element and relaces this element with newRoot.
 * 
 * Returns the old root node.
 **/
xmlNodePtr
domSetDocumentElement( xmlDocPtr doc, xmlNodePtr newRoot ) { 
    return domReplaceChild( (xmlNodePtr)doc, 
                            newRoot, 
                            domDocumentElement( doc )) ;
}

xmlNodePtr
domImportNode( xmlDocPtr doc, xmlNodePtr node, int move ) {
    xmlNodePtr return_node = node;

    if ( node && node->doc != doc ) {
        if ( move ) {
            return_node = domUnbindNode( node );
        }
        else {
            return_node = xmlCopyNode( node, 1 );
        }
        /* tell all children about the new boss */ 
        return_node = domSetOwnerDocument( return_node, doc ); 
    }
 
    return return_node;
}

xmlNodeSetPtr
domGetElementsByTagName( xmlNodePtr n, xmlChar* name ){
    xmlNodeSetPtr rv = NULL;
    xmlNodePtr cld = NULL;

    if ( n != NULL && name != NULL ) {
        cld = n->children;
        while ( cld != NULL ) {
            if ( xmlStrcmp( name, cld->name ) == 0 ){
                if ( rv == NULL ) {
                    rv = xmlXPathNodeSetCreate( cld ) ;
                }
                else {
                    xmlXPathNodeSetAdd( rv, cld );
                }
            }
            cld = cld->next;
        }
    }
  
    return rv;
}


xmlNodeSetPtr
domGetElementsByTagNameNS( xmlNodePtr n, xmlChar* nsURI, xmlChar* name ){
    xmlNodeSetPtr rv = NULL;

    if ( nsURI == NULL ) {
        return domGetElementsByTagName( n, name );
    }
  
    if ( n != NULL && name != NULL  ) {
        xmlNodePtr cld = n->children;
        while ( cld != NULL ) {
            if ( xmlStrcmp( name, cld->name ) == 0 
                 && cld->ns != NULL
                 && xmlStrcmp( nsURI, cld->ns->href ) == 0  ){
                if ( rv == NULL ) {
                    rv = xmlXPathNodeSetCreate( cld ) ;
                }
                else {
                    xmlXPathNodeSetAdd( rv, cld );
                }
            }
            cld = cld->next;
        }
    }
  
    return rv;
}

xmlNodePtr
domSetOwnerDocument( xmlNodePtr self, xmlDocPtr newDoc ) {
    if ( self != NULL ) {
        xmlNodePtr cNode = self->children;
        xmlNodePtr pNode = (xmlNodePtr)self->properties;
        
        self->doc = newDoc;
        while ( cNode != NULL ) {
            domSetOwnerDocument( cNode, newDoc );
            cNode = cNode->next;
        }

        while ( pNode != NULL ) {
          domSetOwnerDocument( cNode, newDoc );
          pNode = pNode->next;
        }
    }

    return self;
}

xmlNsPtr
domNewNs ( xmlNodePtr elem , xmlChar *prefix, xmlChar *href ) {
    xmlNsPtr ns = NULL;
  
    if (elem != NULL) {
        ns = xmlSearchNs( elem->doc, elem, prefix );
    }
    /* prefix is not in use */
    if (ns == NULL) {
        ns = xmlNewNs( elem , href , prefix );
    } else {
        /* prefix is in use; if it has same URI, let it go, otherwise it's
           an error */
        if (!xmlStrEqual(href, ns->href)) {
            ns = NULL;
        }
    }
    return ns;
}

/* This routine may or may not make it into libxml2; Matt wanted it in
   here to be nice to those with older libxml2 installations.
   This instance is renamed from xmlHasNsProp to domHasNsProp. */
/**
 * xmlHasNsProp:
 * @node:  the node
 * @name:  the attribute name
 * @namespace:  the URI of the namespace
 *
 * Search for an attribute associated to a node
 * This attribute has to be anchored in the namespace specified.
 * This does the entity substitution.
 * This function looks in DTD attribute declaration for #FIXED or
 * default declaration values unless DTD use has been turned off.
 *
 * Returns the attribute or the attribute declaration or NULL
 *     if neither was found.
 */
xmlAttrPtr
domHasNsProp(xmlNodePtr node, const xmlChar *name, const xmlChar *namespace) {
    xmlAttrPtr prop;
    xmlDocPtr doc;
    xmlNsPtr ns;
    
    if (node == NULL)
        return(NULL);
    
    prop = node->properties;
    if (namespace == NULL)
        return(xmlHasProp(node, name));
    while (prop != NULL) {
        /*
         * One need to have
         *   - same attribute names
         *   - and the attribute carrying that namespace
         *         or
         
         SJT: This following condition is wrong IMHO; I reported it as a bug on libxml2
         
         *         no namespace on the attribute and the element carrying it
         */
        if ((xmlStrEqual(prop->name, name)) &&
            (/* ((prop->ns == NULL) && (node->ns != NULL) &&
                (xmlStrEqual(node->ns->href, namespace))) || */
             ((prop->ns != NULL) &&
              (xmlStrEqual(prop->ns->href, namespace))))) {
            return(prop);
        }
        prop = prop->next;
    }
  
#if 0
    /* xmlCheckDTD is static in libxml/tree.c; it is set there to 1
       and never changed, so commenting this out doesn't change the
       behaviour */
    if (!xmlCheckDTD) return(NULL);
#endif
  
    /*
     * Check if there is a default declaration in the internal
     * or external subsets
     */
    doc =  node->doc;
    if (doc != NULL) {
        if (doc->intSubset != NULL) {
            xmlAttributePtr attrDecl;
      
            attrDecl = xmlGetDtdAttrDesc(doc->intSubset, node->name, name);
            if ((attrDecl == NULL) && (doc->extSubset != NULL))
                attrDecl = xmlGetDtdAttrDesc(doc->extSubset, node->name, name);
            
            if ((attrDecl != NULL) && (attrDecl->prefix != NULL)) {
                /*
                 * The DTD declaration only allows a prefix search
                 */
                ns = xmlSearchNs(doc, node, attrDecl->prefix);
                if ((ns != NULL) && (xmlStrEqual(ns->href, namespace)))
                    return((xmlAttrPtr) attrDecl);
            }
        }
    }
    return(NULL);
}

xmlAttrPtr 
domSetAttributeNode( xmlNodePtr node, xmlAttrPtr attr ) {
    if ( attr != NULL && attr->type != XML_ATTRIBUTE_NODE )
        return NULL;
    if ( node == NULL || attr == NULL ) {
        return attr;
    }
    if ( node == attr->parent ) {
        return attr; /* attribute is allready part of the node */
    }  
    if ( attr->doc != node->doc ){
        attr = (xmlAttrPtr) domImportNode( node->doc, (xmlNodePtr) attr, 1 ); 
    } 
    else {
        attr = (xmlAttrPtr)domUnbindNode( (xmlNodePtr) attr );
    }

    /* stolen from libxml2 */
    if ( attr != NULL ) {
        if (node->properties == NULL) {
            node->properties = attr;
        } else {
            xmlAttrPtr prev = node->properties;
            
            while (prev->next != NULL) prev = prev->next;
            prev->next = attr;
            attr->prev = prev;
        }
    }

    return attr;
}
