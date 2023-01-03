

if(window.contextOptions){
    let interval = setInterval(function(){
        if(document.getElementsByTagName('head').length > 0){
            clearInterval(interval);
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            var head = document.getElementsByTagName('head')[0];
            head.appendChild(meta);
            var style = document.createElement('style');
            style.innerHTML = 'html {font-size: 16px;}';
            style.setAttribute('type', 'text/css');
            document.head.appendChild(style);
        }
    }, 10);
}
